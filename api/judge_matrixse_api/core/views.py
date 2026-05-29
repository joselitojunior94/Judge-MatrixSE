"""
JudgeMatrixSE — API views.

Role enforcement is applied on every evaluation-scoped endpoint.
See core/permissions.py for role helpers.
"""
from collections import Counter, defaultdict
import hashlib
import re

from django.contrib.auth.models import User
from django.db import models as djm, transaction
from django.http import HttpResponse
from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import viewsets, status
from rest_framework.decorators import api_view, parser_classes, permission_classes, action
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

import csv, io, json, os
import numpy as np

from .gamification import evaluation_ranking, platform_ranking
from .llm_service import call as llm_call
from .models import (
    Codebook, ConsistencyFinding, Dataset, DatasetColumn, DatasetItem,
    DisagreementDiagnosis, Evaluation, EvaluationMessage, FriendInvitation,
    Judgment,
    LabelNormalizationProposal, LLMRun, Notification, Review, RoutingSuggestion,
    ThreatsValidityReport, UserFollow, UserProfile,
)
from .permissions import get_eval_role, IsEvaluationOwner, IsJudgeOrOwner, IsReviewerOrOwner
from .serializers import (
    DatasetSerializer, DatasetItemSerializer, EvaluationSerializer,
    FriendInvitationSerializer, JudgmentSerializer, ReviewSerializer,
    PublicUserProfileSerializer, UserSearchSerializer, UserProfileDetailSerializer,
    CodebookSerializer, ConsistencyFindingSerializer,
    DisagreementDiagnosisSerializer, LabelNormalizationProposalSerializer,
    RoutingSuggestionSerializer, ThreatsValidityReportSerializer,
    EvaluationMessageSerializer, NotificationSerializer, PublicEvaluationSerializer,
    UserFollowSerializer,
)
from urllib.request import Request, urlopen


# ---------------------------------------------------------------------------
# CSV parsing helpers
# ---------------------------------------------------------------------------
def _normalize_header(raw):
    h = [(str(x).strip() or None) for x in raw]
    return [v if v else f'col_{i}' for i, v in enumerate(h)]


def _normalize_row(row, H):
    row = [str(x) for x in row]
    if len(row) > H:
        return row[:H]
    elif len(row) < H:
        return row + [''] * (H - len(row))
    return row


def _json_default(value):
    if hasattr(value, 'isoformat'):
        return value.isoformat()
    return str(value)


def _input_hash(payload):
    blob = json.dumps(payload, sort_keys=True, default=_json_default)
    return hashlib.sha256(blob.encode('utf-8')).hexdigest()


def _parse_llm_json(text):
    try:
        return json.loads(text)
    except Exception:
        return {'raw_text': text}


def _store_llm_run(*, feature, prompt, prompt_version, result, user, dataset=None, evaluation=None, input_payload=None):
    output_json = _parse_llm_json(result.text)
    is_error = isinstance(output_json, dict) and bool(output_json.get('error'))
    return LLMRun.objects.create(
        feature=feature,
        provider=result.provider,
        model_name=result.model,
        prompt_version=result.prompt_version,
        input_hash=_input_hash(input_payload or prompt),
        prompt=prompt,
        output_text=result.text,
        output_json=output_json if isinstance(output_json, dict) else {'value': output_json},
        raw_response=result.raw,
        duration_ms=max(result.duration_ms, 0),
        status='error' if is_error else 'completed',
        error=output_json.get('error', '') if isinstance(output_json, dict) else '',
        created_by=user,
        dataset=dataset,
        evaluation=evaluation,
    )


def _first_text_value(data):
    for key in ('text', 'body', 'description', 'message', 'title', 'summary'):
        if key in data and str(data[key]).strip():
            return str(data[key])
    for value in data.values():
        if str(value).strip():
            return str(value)
    return ''


def _published_codebook(ev):
    return ev.codebooks.filter(status='published').order_by('-version').first()


def _notify(recipient, *, kind, title, body='', actor=None, evaluation=None, data=None):
    if recipient is None:
        return None
    if actor is not None and actor.pk == recipient.pk and kind == 'activity':
        return None
    return Notification.objects.create(
        recipient=recipient,
        actor=actor,
        evaluation=evaluation,
        kind=kind,
        title=title,
        body=body,
        data=data or {},
    )


def _notify_evaluation_members(ev, *, kind, title, body, actor=None, data=None, include_actor=False):
    for user in _evaluation_members(ev):
        if not include_actor and actor is not None and user.pk == actor.pk:
            continue
        _notify(
            user,
            kind=kind,
            title=title,
            body=body,
            actor=actor,
            evaluation=ev,
            data=data,
        )


def _evaluation_members(ev):
    users = {ev.owner_id: ev.owner}
    for user in list(ev.judges.all()) + list(ev.reviewers.all()) + list(ev.viewers.all()):
        users[user.pk] = user
    return list(users.values())


def _normalize_orcid(value):
    raw = str(value or '').strip()
    if not raw:
        return ''
    match = re.search(r'(\d{4}-\d{4}-\d{4}-[\dXx]{4})', raw)
    if match:
        return match.group(1).upper()
    compact = re.sub(r'[^0-9Xx]', '', raw).upper()
    if len(compact) == 16:
        return f'{compact[0:4]}-{compact[4:8]}-{compact[8:12]}-{compact[12:16]}'
    return raw


def _normalize_label_list(payload):
    if isinstance(payload, list):
        raw = payload
    elif payload is None:
        raw = []
    else:
        raw = str(payload).split(',')
    labels = []
    seen = set()
    for item in raw:
        label = str(item).strip()
        if label and label.lower() not in seen:
            labels.append(label)
            seen.add(label.lower())
    return labels


# ---------------------------------------------------------------------------
# Phase 0 — Auth / profile
# ---------------------------------------------------------------------------
@api_view(['GET'])
@permission_classes([AllowAny])
def health(request):
    return Response({'ok': True, 'service': 'judgematrixse-api'})


@api_view(['POST'])
@permission_classes([AllowAny])
def register(request):
    username = request.data.get('username', '').strip()
    password = request.data.get('password', '')
    if not username or not password:
        return Response({'detail': 'username and password required'}, status=400)
    if User.objects.filter(username=username).exists():
        return Response({'detail': 'username already exists'}, status=400)
    u = User.objects.create_user(username=username, password=password)
    return Response({'id': u.id, 'username': u.username}, status=201)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def me(request):
    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    return Response(UserProfileDetailSerializer(profile, context={'request': request}).data)


@api_view(['PATCH'])
@parser_classes([JSONParser, MultiPartParser, FormParser])
@permission_classes([IsAuthenticated])
def update_me(request):
    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    s = UserProfileDetailSerializer(
        profile,
        data=request.data,
        partial=True,
        context={'request': request},
    )
    s.is_valid(raise_exception=True)
    s.save()
    _notify(
        request.user,
        kind='profile',
        title='Profile updated',
        body='Your public profile information was updated.',
        actor=request.user,
        data={'section': 'profile'},
    )
    return Response(s.data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def notifications(request):
    qs = request.user.notifications.select_related('actor', 'actor__profile', 'evaluation')[:80]
    unread = request.user.notifications.filter(read_at__isnull=True).count()
    return Response({
        'unread': unread,
        'notifications': NotificationSerializer(qs, many=True, context={'request': request}).data,
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def mark_notifications_read(request):
    ids = request.data.get('ids') or []
    qs = request.user.notifications.filter(read_at__isnull=True)
    if ids:
        qs = qs.filter(id__in=ids)
    updated = qs.update(read_at=timezone.now())
    return Response({'ok': True, 'updated': updated})


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def sync_publications(request):
    """Fetch publications from ORCID when an ORCID id is present.

    Google Scholar has no stable official public API, so Scholar is stored as
    a verified link for now. ORCID sync gives us a reproducible, official path.
    """
    profile, _ = UserProfile.objects.get_or_create(user=request.user)
    orcid = _normalize_orcid(request.data.get('orcid') or profile.orcid)
    if not orcid:
        return Response({'detail': 'ORCID is required to sync publications.'}, status=400)

    profile.orcid = orcid
    try:
        req = Request(
            f'https://pub.orcid.org/v3.0/{orcid}/works',
            headers={
                'Accept': 'application/json',
                'User-Agent': 'JudgeMatrixSE/1.0 (ORCID publication sync)',
            },
        )
        with urlopen(req, timeout=8) as res:
            raw = json.loads(res.read().decode('utf-8'))
        publications = []
        for group in raw.get('group', [])[:40]:
            summary = (group.get('work-summary') or [{}])[0]
            title = (((summary.get('title') or {}).get('title') or {}).get('value') or '').strip()
            year = (((summary.get('publication-date') or {}).get('year') or {}).get('value') or '')
            journal = (((summary.get('journal-title') or {}).get('value')) or '')
            put_code = summary.get('put-code')
            if title:
                publications.append({
                    'title': title,
                    'year': year,
                    'venue': journal,
                    'source': 'orcid',
                    'url': f'https://orcid.org/{orcid}/work/{put_code}' if put_code else f'https://orcid.org/{orcid}',
                })
    except Exception as exc:
        return Response({'detail': f'ORCID sync failed: {exc}'}, status=502)

    profile.publications = publications
    profile.save(update_fields=['orcid', 'publications'])
    _notify(
        request.user,
        kind='profile',
        title='ORCID publications synced',
        body=f'{len(publications)} publication(s) were imported from ORCID.',
        actor=request.user,
        data={'section': 'publications', 'source': 'orcid', 'count': len(publications)},
    )
    return Response(UserProfileDetailSerializer(profile, context={'request': request}).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def user_search(request):
    """GET /api/users/?search=<q>  — find collaborators by username/name."""
    q = request.query_params.get('search', '').strip()
    qs = User.objects.exclude(pk=request.user.pk).order_by('username')
    if q:
        qs = qs.filter(
            djm.Q(username__icontains=q)
            | djm.Q(first_name__icontains=q)
            | djm.Q(last_name__icontains=q)
            | djm.Q(profile__display_name__icontains=q)
            | djm.Q(profile__first_name__icontains=q)
            | djm.Q(profile__last_name__icontains=q)
        )
    return Response(
        UserSearchSerializer(
            qs.select_related('profile')[:20],
            many=True,
            context={'request': request},
        ).data
    )


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def public_user_profile(request, user_id):
    user = get_object_or_404(User, pk=user_id)
    profile, _ = UserProfile.objects.get_or_create(user=user)
    return Response(PublicUserProfileSerializer(profile, context={'request': request}).data)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def friends(request):
    following = UserFollow.objects.filter(follower=request.user).select_related(
        'following', 'following__profile', 'follower', 'follower__profile',
    )
    followers = UserFollow.objects.filter(following=request.user).select_related(
        'following', 'following__profile', 'follower', 'follower__profile',
    )
    return Response({
        'following': UserFollowSerializer(following, many=True, context={'request': request}).data,
        'followers': UserFollowSerializer(followers, many=True, context={'request': request}).data,
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def invite_friend(request):
    receiver_id = request.data.get('user_id')
    username = request.data.get('username')
    if receiver_id:
        receiver = get_object_or_404(User, pk=receiver_id)
    elif username:
        receiver = get_object_or_404(User, username=username)
    else:
        return Response({'detail': 'user_id or username required.'}, status=400)
    if receiver.pk == request.user.pk:
        return Response({'detail': 'You cannot follow yourself.'}, status=400)
    follow, created = UserFollow.objects.get_or_create(
        follower=request.user,
        following=receiver,
    )
    if created:
        _notify(
            receiver,
            kind='follow',
            title='New follower',
            body=f'{request.user.username} started following you.',
            actor=request.user,
            data={'follower_id': request.user.pk},
        )
        _notify(
            request.user,
            kind='activity',
            title='You are following a collaborator',
            body=f'You started following {receiver.username}.',
            actor=request.user,
            data={'following_id': receiver.pk},
        )
    return Response(UserFollowSerializer(follow, context={'request': request}).data, status=201)


@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def unfollow_user(request, user_id):
    deleted, _ = UserFollow.objects.filter(
        follower=request.user,
        following_id=user_id,
    ).delete()
    if deleted:
        followed = User.objects.filter(pk=user_id).first()
        if followed is not None:
            _notify(
                followed,
                kind='follow',
                title='Follower removed',
                body=f'{request.user.username} stopped following you.',
                actor=request.user,
                data={'follower_id': request.user.pk},
            )
    return Response({'ok': True, 'deleted': deleted})


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def user_follow_lists(request, user_id):
    user = get_object_or_404(User, pk=user_id)
    following = UserFollow.objects.filter(follower=user).select_related(
        'following', 'following__profile', 'follower', 'follower__profile',
    )
    followers = UserFollow.objects.filter(following=user).select_related(
        'following', 'following__profile', 'follower', 'follower__profile',
    )
    return Response({
        'following': UserFollowSerializer(following, many=True, context={'request': request}).data,
        'followers': UserFollowSerializer(followers, many=True, context={'request': request}).data,
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def respond_friend_invite(request, invitation_id):
    inv = get_object_or_404(FriendInvitation, pk=invitation_id, receiver=request.user)
    status_value = request.data.get('status')
    if status_value not in ('accepted', 'declined'):
        return Response({'detail': 'status must be accepted or declined.'}, status=400)
    inv.status = status_value
    inv.save(update_fields=['status', 'updated_at'])
    return Response(FriendInvitationSerializer(inv, context={'request': request}).data)


# ---------------------------------------------------------------------------
# Phase 2 — Dataset upload & mapping
# ---------------------------------------------------------------------------
class UploadCsvView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, dataset_id=None):
        f       = request.FILES.get('file')
        meta_raw = request.POST.get('meta')
        if not f or not meta_raw:
            return Response({'detail': 'file and meta are required'}, status=400)
        try:
            meta = json.loads(meta_raw)
        except Exception:
            return Response({'detail': 'invalid meta json'}, status=400)

        delimiter = meta.get('delimiter', ',')
        encoding  = meta.get('encoding', 'UTF-8')
        blob = f.read(); f.seek(0)

        with transaction.atomic():
            if dataset_id:
                ds = get_object_or_404(Dataset, pk=dataset_id, created_by=request.user)
                ds.version += 1
                ds.original_file.save(f'{ds.id}_v{ds.version}.csv', f)
                ds.delimiter = delimiter; ds.encoding = encoding; ds.save()
                ds.items.all().delete()
            else:
                name = meta.get('dataset_name') or f.name
                ds = Dataset.objects.create(
                    name=name, created_by=request.user,
                    delimiter=delimiter, encoding=encoding,
                )
                ds.original_file.save(f'{ds.id}_v1.csv', f); ds.save()

            try:
                text = blob.decode('utf-8') if encoding.upper() == 'UTF-8' else blob.decode('latin1')
            except Exception:
                text = blob.decode('utf-8', errors='ignore')

            reader = csv.reader(io.StringIO(text), delimiter=('\t' if delimiter == '\t' else delimiter))
            rows   = list(reader)
            if not rows:
                return Response({'detail': 'empty csv'}, status=400)

            header = _normalize_header(rows[0])
            H      = len(header)
            items  = [
                DatasetItem(dataset=ds, row_index=i, data=dict(zip(header, _normalize_row(r, H))))
                for i, r in enumerate(rows[1:])
            ]
            if items:
                DatasetItem.objects.bulk_create(items, batch_size=1000)

        return Response({'dataset_id': ds.id, 'version': ds.version})


class DatasetViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = DatasetSerializer

    def get_queryset(self):
        user = self.request.user
        return Dataset.objects.filter(
            djm.Q(created_by=user)
            | djm.Q(evaluations__owner=user)
            | djm.Q(evaluations__judges=user)
            | djm.Q(evaluations__reviewers=user)
            | djm.Q(evaluations__viewers=user)
        ).distinct().select_related('created_by').prefetch_related('columns')

    @action(detail=True, methods=['get'])
    def items(self, request, pk=None):
        ds = self.get_object()
        qs = ds.items.all().order_by('row_index')
        page      = int(request.query_params.get('page', 1))
        page_size = int(request.query_params.get('page_size', 50))
        s = (page - 1) * page_size; e = s + page_size
        return Response({
            'count': qs.count(), 'page': page,
            'results': DatasetItemSerializer(qs[s:e], many=True).data,
        })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def save_mapping(request, dataset_id, version):
    ds = get_object_or_404(Dataset, pk=dataset_id, created_by=request.user)
    cols = request.data.get('columns', [])
    ds.columns.all().delete()
    to_create = [
        DatasetColumn(
            dataset=ds,
            name_in_file=c.get('name_in_file') or c.get('mapped_name'),
            mapped_name=c.get('mapped_name') or c.get('name_in_file'),
            role=c.get('role', 'FEATURE'),
            dtype=c.get('dtype', 'string'),
            required=bool(c.get('required', False)),
        ) for c in cols
    ]
    if to_create:
        DatasetColumn.objects.bulk_create(to_create, batch_size=500)
    return Response({'ok': True, 'count': len(to_create)})


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def generate_label_normalization(request, dataset_id):
    ds = get_object_or_404(Dataset, pk=dataset_id, created_by=request.user)
    label_column = request.data.get('label_column')
    if not label_column:
        label_col = ds.columns.filter(role='LABEL').first()
        label_column = label_col.mapped_name if label_col else None
    if not label_column:
        return Response({'detail': 'label_column is required.'}, status=400)

    labels = sorted({
        str(item.data.get(label_column, '')).strip()
        for item in ds.items.all()
        if str(item.data.get(label_column, '')).strip()
    })
    if not labels:
        return Response({'detail': 'No label values found for this column.'}, status=400)

    payload = {'dataset_id': ds.id, 'label_column': label_column, 'distinct_labels': labels}
    prompt = (
        "You are a semantic label normalization assistant for a CSV import wizard. "
        "The owner has not started an evaluation yet. Detect synonymous or variant "
        "label strings and propose a consolidation mapping. Do not apply anything; "
        "the owner must confirm, edit, or reject the mapping.\n\n"
        f"Distinct labels:\n{json.dumps(labels, indent=2)}\n\n"
        "Return JSON with keys: groups [{canonical, variants, confidence, reason}], "
        "normalisation_map {raw_label: canonical_label}, and summary."
    )
    result = llm_call(prompt, prompt_version='label-normalization-import-v2')
    run = _store_llm_run(
        feature='label_normalization',
        prompt=prompt,
        prompt_version='label-normalization-import-v2',
        result=result,
        user=request.user,
        dataset=ds,
        input_payload=payload,
    )
    out = run.output_json
    mapping = out.get('normalisation_map') or out.get('normalization_map') or {}
    if not isinstance(mapping, dict) or not mapping:
        mapping = {label: label for label in labels}
    proposal = LabelNormalizationProposal.objects.create(
        dataset=ds,
        llm_run=run,
        label_column=label_column,
        distinct_labels=labels,
        proposed_mapping=mapping,
        created_by=request.user,
    )
    return Response(LabelNormalizationProposalSerializer(proposal).data, status=201)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def decide_label_normalization(request, proposal_id):
    proposal = get_object_or_404(
        LabelNormalizationProposal,
        pk=proposal_id,
        dataset__created_by=request.user,
    )
    decision = request.data.get('status')
    if decision not in ('approved', 'rejected'):
        return Response({'detail': 'status must be approved or rejected.'}, status=400)

    proposal.status = decision
    proposal.decided_by = request.user
    proposal.decided_at = timezone.now()
    if decision == 'approved':
        mapping = request.data.get('mapping') or proposal.proposed_mapping
        if not isinstance(mapping, dict):
            return Response({'detail': 'mapping must be an object.'}, status=400)
        proposal.approved_mapping = mapping
        changed = 0
        with transaction.atomic():
            for item in proposal.dataset.items.select_for_update():
                raw = str(item.data.get(proposal.label_column, '')).strip()
                if raw in mapping and mapping[raw] != raw:
                    item.data[proposal.label_column] = mapping[raw]
                    item.save(update_fields=['data'])
                    changed += 1
        proposal.save(update_fields=['status', 'decided_by', 'decided_at', 'approved_mapping'])
        data = LabelNormalizationProposalSerializer(proposal).data
        data['items_changed'] = changed
        return Response(data)

    proposal.save(update_fields=['status', 'decided_by', 'decided_at'])
    return Response(LabelNormalizationProposalSerializer(proposal).data)


# ---------------------------------------------------------------------------
# Phase 3 — Evaluation CRUD
# ---------------------------------------------------------------------------
class EvaluationViewSet(viewsets.ModelViewSet):
    serializer_class = EvaluationSerializer

    def get_queryset(self):
        u = self.request.user
        return (Evaluation.objects
                .filter(djm.Q(owner=u) | djm.Q(judges=u) | djm.Q(reviewers=u) | djm.Q(viewers=u))
                .distinct()
                .select_related('dataset', 'owner')
                .prefetch_related('judges', 'reviewers', 'viewers'))

    def _member_ids(self, ev):
        return {
            'judges': set(ev.judges.values_list('id', flat=True)),
            'reviewers': set(ev.reviewers.values_list('id', flat=True)),
            'viewers': set(ev.viewers.values_list('id', flat=True)),
        }

    def _require_owner(self, ev):
        if ev.owner_id != self.request.user.pk:
            self.permission_denied(self.request, message='Only the owner can modify this evaluation.')

    def create(self, request, *args, **kwargs):
        response = super().create(request, *args, **kwargs)
        ev = Evaluation.objects.get(pk=response.data['id'])
        before = {'judges': {request.user.pk}, 'reviewers': set(), 'viewers': set()}
        self._notify_new_members(ev, before)
        return response

    def update(self, request, *args, **kwargs):
        ev = self.get_object()
        self._require_owner(ev)
        before = self._member_ids(ev)
        response = super().update(request, *args, **kwargs)
        ev.refresh_from_db()
        self._notify_new_members(ev, before)
        return response

    def partial_update(self, request, *args, **kwargs):
        ev = self.get_object()
        self._require_owner(ev)
        before = self._member_ids(ev)
        response = super().partial_update(request, *args, **kwargs)
        ev.refresh_from_db()
        self._notify_new_members(ev, before)
        return response

    def destroy(self, request, *args, **kwargs):
        ev = self.get_object()
        self._require_owner(ev)
        return super().destroy(request, *args, **kwargs)

    def _notify_new_members(self, ev, before):
        role_map = {
            'judges': ('judge', ev.judges.all()),
            'reviewers': ('reviewer', ev.reviewers.all()),
            'viewers': ('viewer', ev.viewers.all()),
        }
        for key, (role, users) in role_map.items():
            for user in users:
                if user.pk not in before[key]:
                    _notify(
                        user,
                        kind='evaluation_invite',
                        title=f'Added as {role}',
                        body=f'You were added to "{ev.name}" as {role}.',
                        actor=self.request.user,
                        evaluation=ev,
                        data={'role': role, 'evaluation_id': ev.id},
                    )


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def public_evaluations(request):
    qs = (
        Evaluation.objects.filter(is_public=True)
        .select_related('dataset', 'owner', 'owner__profile')
        .prefetch_related('judges', 'reviewers', 'viewers')
        .order_by('-updated_at')[:100]
    )
    return Response(PublicEvaluationSerializer(qs, many=True, context={'request': request}).data)


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def join_public_evaluation(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id, is_public=True)
    role = str(request.data.get('role', '')).strip().lower()
    allowed = set(ev.public_join_roles or [])
    if role not in ('judge', 'reviewer', 'viewer'):
        return Response({'detail': 'role must be judge, reviewer, or viewer.'}, status=400)
    if role not in allowed:
        return Response({'detail': f'Joining as {role} is not enabled for this evaluation.'}, status=403)
    if ev.status in ('closed', 'frozen', 'archived'):
        return Response({'detail': f'Evaluation is {ev.status}.'}, status=400)

    if role == 'judge':
        ev.judges.add(request.user)
    elif role == 'reviewer':
        ev.reviewers.add(request.user)
    else:
        ev.viewers.add(request.user)

    _notify(
        ev.owner,
        kind='activity',
        title='New participant joined',
        body=f'{request.user.username} joined "{ev.name}" as {role}.',
        actor=request.user,
        evaluation=ev,
        data={'role': role, 'evaluation_id': ev.id},
    )
    _notify(
        request.user,
        kind='evaluation_invite',
        title='Joined public evaluation',
        body=f'You joined "{ev.name}" as {role}.',
        actor=request.user,
        evaluation=ev,
        data={'role': role, 'evaluation_id': ev.id},
    )
    return Response(PublicEvaluationSerializer(ev, context={'request': request}).data)


def _routing_score_for_item(item):
    text = _first_text_value(item.data)
    length = len(text)
    filled = sum(1 for value in item.data.values() if str(value).strip())
    score = min(1.0, (length / 600.0) + (filled / 30.0))
    contention = 'low' if score < 0.35 else ('medium' if score < 0.65 else 'high')
    judges_needed = 1 if contention == 'low' else (2 if contention == 'medium' else 3)
    return {
        'item_id': item.id,
        'row_index': item.row_index,
        'difficulty_score': round(score, 3),
        'contention': contention,
        'recommended_judges': judges_needed,
    }


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def effort_routing(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if ev.owner_id != request.user.pk:
        return Response({'detail': 'Only the owner can manage routing suggestions.'}, status=403)
    if request.method == 'GET':
        latest = ev.routing_suggestions.first()
        return Response(RoutingSuggestionSerializer(latest).data if latest else {})

    items = list(ev.dataset.items.all().order_by('row_index'))
    if not items:
        return Response({'detail': 'No items available for routing.'}, status=400)
    scores = [_routing_score_for_item(item) for item in items]
    counts = Counter(score['contention'] for score in scores)
    summary = {
        'total_items': len(scores),
        'low_contention_pct': round(counts['low'] / len(scores) * 100, 1),
        'medium_contention_pct': round(counts['medium'] / len(scores) * 100, 1),
        'high_contention_pct': round(counts['high'] / len(scores) * 100, 1),
        'suggestion': (
            f"Route about {round(counts['low'] / len(scores) * 100)}% low-contention items "
            "to one judge and send medium/high-contention items to multiple judges."
        ),
    }
    sample = [
        {
            'item_id': item.id,
            'row_index': item.row_index,
            'text': _first_text_value(item.data)[:800],
            'heuristic_score': scores[index]['difficulty_score'],
        }
        for index, item in enumerate(items[:50])
    ]
    payload = {'evaluation_id': ev.id, 'summary': summary, 'sample': sample}
    prompt = (
        "You are estimating labeling effort before human judges start. "
        "Do not propose labels. Do not mention candidate labels. "
        "Score only expected difficulty/contention and routing effort.\n\n"
        f"Item sample with heuristic scores:\n{json.dumps(sample, indent=2)}\n\n"
        "Return JSON with keys: summary, risks, routing_notes. "
        "All routing remains advisory and must be accepted by the owner."
    )
    result = llm_call(prompt, prompt_version='effort-routing-v1')
    run = _store_llm_run(
        feature='effort_routing',
        prompt=prompt,
        prompt_version='effort-routing-v1',
        result=result,
        user=request.user,
        evaluation=ev,
        input_payload=payload,
    )
    out = run.output_json
    if isinstance(out, dict) and out.get('summary') and not isinstance(out.get('summary'), dict):
        summary['llm_summary'] = out.get('summary')
    suggestion = RoutingSuggestion.objects.create(
        evaluation=ev,
        llm_run=run,
        item_scores=scores,
        summary=summary,
        created_by=request.user,
    )
    return Response(RoutingSuggestionSerializer(suggestion).data, status=201)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def decide_effort_routing(request, suggestion_id):
    suggestion = get_object_or_404(RoutingSuggestion, pk=suggestion_id)
    if suggestion.evaluation.owner_id != request.user.pk:
        return Response({'detail': 'Only the owner can decide routing suggestions.'}, status=403)
    status_value = request.data.get('status')
    if status_value not in ('accepted', 'ignored'):
        return Response({'detail': 'status must be accepted or ignored.'}, status=400)
    suggestion.status = status_value
    suggestion.decided_by = request.user
    suggestion.decided_at = timezone.now()
    suggestion.save(update_fields=['status', 'decided_by', 'decided_at'])
    return Response(RoutingSuggestionSerializer(suggestion).data)


def _codebook_payload(ev):
    grouped = defaultdict(list)
    for judgment in ev.judgments.select_related('item', 'judge').order_by('created_at'):
        grouped[judgment.value].append({
            'item_id': judgment.item_id,
            'row_index': judgment.item.row_index,
            'text': _first_text_value(judgment.item.data)[:900],
            'confidence': judgment.confidence,
            'judge_id': judgment.judge_id,
        })
    return {
        'evaluation_id': ev.id,
        'labels': {
            label: {
                'count': len(items),
                'examples': items[:8],
            }
            for label, items in grouped.items()
        },
    }


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def codebooks(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    role = get_eval_role(request.user, ev)
    if role is None:
        return Response({'detail': 'Not a member.'}, status=403)
    if request.method == 'GET':
        if role == 'owner':
            qs = ev.codebooks.all()
        else:
            qs = ev.codebooks.filter(status='published')
        return Response(CodebookSerializer(qs, many=True).data)

    if ev.owner_id != request.user.pk:
        return Response({'detail': 'Only the owner can generate a codebook.'}, status=403)
    judged_count = ev.judgments.values('item_id').distinct().count()
    min_items = int(os.environ.get('CODEBOOK_MIN_ITEMS', '20'))
    force = bool(request.data.get('force', False))
    if judged_count < min_items and not force:
        return Response({
            'detail': f'At least {min_items} judged items are required.',
            'judged_items': judged_count,
            'required_items': min_items,
        }, status=400)

    payload = _codebook_payload(ev)
    if not payload['labels']:
        return Response({'detail': 'No judgments available for codebook induction.'}, status=400)
    prompt = (
        "You are inducing a draft labeling codebook from already completed human judgments. "
        "Do not create new labels and do not judge unlabeled items. For each observed label, "
        "write an operational definition, representative examples, and edge cases. "
        "This draft must be reviewed by the owner before publication.\n\n"
        f"Grouped judged examples:\n{json.dumps(payload, indent=2, default=_json_default)}\n\n"
        "Return JSON with keys: labels [{name, definition, examples, edge_cases}], "
        "general_guidance, and markdown."
    )
    result = llm_call(prompt, prompt_version='codebook-induction-v2')
    run = _store_llm_run(
        feature='codebook_induction',
        prompt=prompt,
        prompt_version='codebook-induction-v2',
        result=result,
        user=request.user,
        evaluation=ev,
        input_payload=payload,
    )
    content = run.output_json
    labels = content.get('labels') if isinstance(content, dict) else None
    if not labels:
        counts = Counter(ev.judgments.values_list('value', flat=True))
        labels = [
            {
                'name': label,
                'definition': 'Owner should refine this operational definition.',
                'examples': [],
                'edge_cases': [],
            }
            for label in sorted(counts)
        ]
        content = {'labels': labels, 'general_guidance': '', 'markdown': ''}
    markdown = content.get('markdown') or '\n\n'.join(
        f"## {entry.get('name')}\n{entry.get('definition', '')}"
        for entry in labels
        if isinstance(entry, dict)
    )
    version = (ev.codebooks.aggregate(max_version=djm.Max('version'))['max_version'] or 0) + 1
    codebook = Codebook.objects.create(
        evaluation=ev,
        llm_run=run,
        content=content,
        markdown=markdown,
        version=version,
        created_by=request.user,
    )
    return Response(CodebookSerializer(codebook).data, status=201)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def codebook_detail(request, codebook_id):
    codebook = get_object_or_404(Codebook, pk=codebook_id)
    if codebook.evaluation.owner_id != request.user.pk:
        return Response({'detail': 'Only the owner can edit or publish codebooks.'}, status=403)
    content = request.data.get('content')
    markdown = request.data.get('markdown')
    status_value = request.data.get('status')
    if content is not None:
        if not isinstance(content, dict):
            return Response({'detail': 'content must be an object.'}, status=400)
        codebook.content = content
    if markdown is not None:
        codebook.markdown = str(markdown)
    update_fields = ['content', 'markdown']
    if status_value is not None:
        if status_value not in ('draft', 'published', 'archived'):
            return Response({'detail': 'Invalid status.'}, status=400)
        if status_value == 'published':
            Codebook.objects.filter(
                evaluation=codebook.evaluation,
                status='published',
            ).exclude(pk=codebook.pk).update(status='archived')
            codebook.published_by = request.user
            codebook.published_at = timezone.now()
            update_fields.extend(['published_by', 'published_at'])
        codebook.status = status_value
        update_fields.append('status')
    codebook.save(update_fields=list(set(update_fields)))
    return Response(CodebookSerializer(codebook).data)


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def item_disagreement_diagnosis(request, eval_id, item_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    role = get_eval_role(request.user, ev)
    if role is None:
        return Response({'detail': 'Not a member.'}, status=403)
    item = get_object_or_404(DatasetItem, pk=item_id, dataset=ev.dataset)
    latest = ev.disagreement_diagnoses.filter(item=item).first()
    if request.method == 'GET':
        return Response(DisagreementDiagnosisSerializer(latest).data if latest else {})

    if role not in ('owner', 'reviewer'):
        return Response({'detail': 'Only owners and reviewers can diagnose disagreements.'}, status=403)
    judgments = list(ev.judgments.filter(item=item).select_related('judge'))
    labels = sorted({j.value for j in judgments})
    if len(labels) < 2:
        return Response({'detail': 'This item does not have divergent labels.'}, status=400)
    codebook = _published_codebook(ev)
    payload = {
        'evaluation_id': ev.id,
        'item_id': item.id,
        'item_text': _first_text_value(item.data)[:1200],
        'judgments': [
            {
                'judge_id': j.judge_id,
                'label': j.value,
                'confidence': j.confidence,
            }
            for j in judgments
        ],
        'published_codebook': codebook.markdown if codebook else '',
    }
    prompt = (
        "You are diagnosing why human judges disagreed on one already-judged item. "
        "Do not vote, do not identify the correct label, and do not create a new judgment. "
        "Classify the likely cause as exactly one of: text ambiguity, overlap between class "
        "definitions, missing information in the item, likely judge error.\n\n"
        f"Context:\n{json.dumps(payload, indent=2, default=_json_default)}\n\n"
        "Return JSON with keys: cause, explanation, evidence, reviewer_next_step."
    )
    result = llm_call(prompt, prompt_version='disagreement-diagnosis-v2')
    run = _store_llm_run(
        feature='disagreement_diagnosis',
        prompt=prompt,
        prompt_version='disagreement-diagnosis-v2',
        result=result,
        user=request.user,
        evaluation=ev,
        input_payload=payload,
    )
    output = run.output_json
    allowed = {
        'text ambiguity',
        'overlap between class definitions',
        'missing information in the item',
        'likely judge error',
    }
    cause = str(output.get('cause', '')).strip().lower() if isinstance(output, dict) else ''
    if cause not in allowed:
        cause = 'text ambiguity'
    explanation = output.get('explanation') if isinstance(output, dict) else ''
    if not explanation:
        explanation = 'The LLM response did not include a structured explanation; inspect the stored payload.'
    diagnosis = DisagreementDiagnosis.objects.create(
        evaluation=ev,
        item=item,
        llm_run=run,
        cause=cause,
        explanation=str(explanation),
        payload=output if isinstance(output, dict) else {'raw': output},
        created_by=request.user,
    )
    return Response(DisagreementDiagnosisSerializer(diagnosis).data, status=201)


def _token_overlap(a, b):
    ta = {part.lower() for part in str(a).split() if len(part) > 2}
    tb = {part.lower() for part in str(b).split() if len(part) > 2}
    if not ta or not tb:
        return 0
    return len(ta & tb) / len(ta | tb)


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def consistency_audit(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    role = get_eval_role(request.user, ev)
    if role is None:
        return Response({'detail': 'Not a member.'}, status=403)
    judge_id = request.query_params.get('judge_id') or request.data.get('judge_id')
    if not judge_id:
        return Response({'detail': 'judge_id is required.'}, status=400)
    judge = get_object_or_404(User, pk=judge_id)
    if not ev.judges.filter(pk=judge.pk).exists() and ev.owner_id != judge.pk:
        return Response({'detail': 'User is not a judge in this evaluation.'}, status=400)

    if request.method == 'GET':
        findings = ev.consistency_findings.filter(judge=judge)
        return Response(ConsistencyFindingSerializer(findings, many=True).data)

    if role not in ('owner', 'reviewer'):
        return Response({'detail': 'Only owners and reviewers can run consistency audits.'}, status=403)
    judgments = list(ev.judgments.filter(judge=judge).select_related('item'))
    candidates = []
    for i, left in enumerate(judgments):
        for right in judgments[i + 1:]:
            if left.value == right.value:
                continue
            left_text = _first_text_value(left.item.data)
            right_text = _first_text_value(right.item.data)
            overlap = _token_overlap(left_text, right_text)
            if overlap >= 0.25 or left.item.row_index % 10 == right.item.row_index % 10:
                candidates.append({
                    'item_a': left.item_id,
                    'item_b': right.item_id,
                    'row_a': left.item.row_index,
                    'row_b': right.item.row_index,
                    'label_a': left.value,
                    'label_b': right.value,
                    'text_a': left_text[:700],
                    'text_b': right_text[:700],
                    'similarity': round(overlap, 3),
                })
    candidates = sorted(candidates, key=lambda x: x['similarity'], reverse=True)[:20]
    payload = {'evaluation_id': ev.id, 'judge_id': judge.pk, 'pairs': candidates}
    prompt = (
        "You are auditing intra-judge consistency after human judgments already exist. "
        "Find near-identical item pairs that the same judge labeled differently. "
        "Do not decide the correct label. Return pairs that deserve human review.\n\n"
        f"Candidate pairs:\n{json.dumps(payload, indent=2, default=_json_default)}\n\n"
        "Return JSON with key findings [{item_a, item_b, justification}]."
    )
    result = llm_call(prompt, prompt_version='intra-judge-consistency-v2')
    run = _store_llm_run(
        feature='consistency_audit',
        prompt=prompt,
        prompt_version='intra-judge-consistency-v2',
        result=result,
        user=request.user,
        evaluation=ev,
        input_payload=payload,
    )
    output = run.output_json
    findings_payload = output.get('findings') if isinstance(output, dict) else None
    if not isinstance(findings_payload, list) or not findings_payload:
        findings_payload = [
            {
                'item_a': pair['item_a'],
                'item_b': pair['item_b'],
                'justification': 'These items look similar but received different labels from the same judge.',
            }
            for pair in candidates[:10]
        ]
    by_pair = {(pair['item_a'], pair['item_b']): pair for pair in candidates}
    created = []
    for finding in findings_payload:
        pair = by_pair.get((finding.get('item_a'), finding.get('item_b')))
        if not pair:
            continue
        obj = ConsistencyFinding.objects.create(
            evaluation=ev,
            judge=judge,
            llm_run=run,
            item_a_id=pair['item_a'],
            item_b_id=pair['item_b'],
            label_a=pair['label_a'],
            label_b=pair['label_b'],
            justification=str(finding.get('justification') or ''),
            created_by=request.user,
        )
        created.append(obj)
    return Response(ConsistencyFindingSerializer(created, many=True).data, status=201)


@api_view(['PATCH'])
@permission_classes([IsAuthenticated])
def consistency_finding_detail(request, finding_id):
    finding = get_object_or_404(ConsistencyFinding, pk=finding_id)
    role = get_eval_role(request.user, finding.evaluation)
    if role not in ('owner', 'reviewer') and finding.judge_id != request.user.pk:
        return Response({'detail': 'Not allowed to resolve this finding.'}, status=403)
    status_value = request.data.get('status')
    if status_value not in ('open', 'corrected', 'genuinely_different', 'dismissed'):
        return Response({'detail': 'Invalid status.'}, status=400)
    finding.status = status_value
    finding.feedback = request.data.get('feedback', finding.feedback)
    if status_value != 'open':
        finding.resolved_by = request.user
        finding.resolved_at = timezone.now()
    finding.save(update_fields=['status', 'feedback', 'resolved_by', 'resolved_at'])
    return Response(ConsistencyFindingSerializer(finding).data)


# ---------------------------------------------------------------------------
# Phase 3 — Evaluation items (all members can list)
# ---------------------------------------------------------------------------
class EvaluationItemsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, eval_id):
        ev = get_object_or_404(Evaluation, pk=eval_id)
        if get_eval_role(request.user, ev) is None:
            return Response({'detail': 'Not a member of this evaluation.'}, status=403)

        role = get_eval_role(request.user, ev)
        qs = ev.dataset.items.all().order_by('row_index')
        page      = int(request.query_params.get('page', 1))
        page_size = int(request.query_params.get('page_size', 50))
        s = (page - 1) * page_size; e = s + page_size
        page_items = list(qs[s:e])
        serialized = DatasetItemSerializer(page_items, many=True).data

        judgments = {
            j.item_id: j
            for j in Judgment.objects.filter(
                evaluation=ev,
                judge=request.user,
                item_id__in=[item.id for item in page_items],
            )
        }
        reviews = {
            r.item_id: r
            for r in Review.objects.filter(
                evaluation=ev,
                reviewer=request.user,
                item_id__in=[item.id for item in page_items],
            )
        }
        for row in serialized:
            item_id = row['id']
            judgment = judgments.get(item_id)
            review = reviews.get(item_id)
            row['current_user_judgment'] = (
                JudgmentSerializer(judgment).data if judgment else None
            )
            row['current_user_review'] = (
                ReviewSerializer(review).data if review else None
            )
            row['current_user_status'] = (
                'labeled' if judgment else ('reviewed' if review else 'pending')
            )

        if role in ('owner', 'judge'):
            completed = Judgment.objects.filter(evaluation=ev, judge=request.user).count()
        elif role == 'reviewer':
            completed = Review.objects.filter(evaluation=ev, reviewer=request.user).count()
        else:
            completed = 0
        return Response({
            'count': qs.count(), 'page': page,
            'completed_count': completed,
            'results': serialized,
        })


# ---------------------------------------------------------------------------
# Phase 4 — Judgments (judge/owner only to write; member to read)
# ---------------------------------------------------------------------------
class JudgmentView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, eval_id, item_id):
        """GET — list all judgments for this item (any evaluation member)."""
        ev   = get_object_or_404(Evaluation, pk=eval_id)
        role = get_eval_role(request.user, ev)
        if role is None:
            return Response({'detail': 'Not a member.'}, status=403)
        item  = get_object_or_404(DatasetItem, pk=item_id, dataset=ev.dataset)
        judgs = Judgment.objects.filter(evaluation=ev, item=item).select_related('judge')
        return Response(JudgmentSerializer(judgs, many=True).data)

    def post(self, request, eval_id, item_id):
        """POST — submit/update a judgment (judge or owner only)."""
        ev   = get_object_or_404(Evaluation, pk=eval_id)
        role = get_eval_role(request.user, ev)
        if role not in ('owner', 'judge'):
            return Response({'detail': 'Only judges and the owner can submit judgments.'}, status=403)
        if ev.status in ('closed', 'frozen', 'archived'):
            return Response({'detail': f'Evaluation is {ev.status}.'}, status=400)

        item = get_object_or_404(DatasetItem, pk=item_id, dataset=ev.dataset)
        labels = _normalize_label_list(request.data.get('labels', request.data.get('value')))
        if not ev.allow_multiple_labels and len(labels) > 1:
            return Response({'detail': 'This evaluation allows only one label per item.'}, status=400)
        val = ', '.join(labels)
        conf = request.data.get('confidence')
        if not labels:
            return Response({'detail': 'value is required'}, status=400)

        Judgment.objects.update_or_create(
            evaluation=ev, item=item, judge=request.user,
            defaults={'value': val, 'labels': labels, 'confidence': conf},
        )
        _notify(
            request.user,
            kind='points',
            title='+10 points for judging',
            body=f'Your judgment in "{ev.name}" was recorded.',
            actor=request.user,
            evaluation=ev,
            data={'points': 10, 'activity': 'judgment', 'evaluation_id': ev.id},
        )
        _notify_evaluation_members(
            ev,
            kind='activity',
            title='New judgment submitted',
            body=f'{request.user.username} submitted a judgment in "{ev.name}".',
            actor=request.user,
            data={'activity': 'judgment', 'evaluation_id': ev.id, 'item_id': item.id},
        )
        return Response({'ok': True})


# ---------------------------------------------------------------------------
# Phase 5 — Reviews (reviewer/owner only to write; member to read)
# ---------------------------------------------------------------------------
class ReviewView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request, eval_id, item_id):
        """GET — list all reviews for this item (any evaluation member)."""
        ev   = get_object_or_404(Evaluation, pk=eval_id)
        role = get_eval_role(request.user, ev)
        if role is None:
            return Response({'detail': 'Not a member.'}, status=403)
        item    = get_object_or_404(DatasetItem, pk=item_id, dataset=ev.dataset)
        reviews = Review.objects.filter(evaluation=ev, item=item).select_related('reviewer')
        return Response(ReviewSerializer(reviews, many=True).data)

    def post(self, request, eval_id, item_id):
        """POST — submit/update a review (reviewer or owner only)."""
        ev   = get_object_or_404(Evaluation, pk=eval_id)
        role = get_eval_role(request.user, ev)
        if role not in ('owner', 'reviewer'):
            return Response({'detail': 'Only reviewers and the owner can submit reviews.'}, status=403)
        if ev.status in ('closed', 'frozen', 'archived'):
            return Response({'detail': f'Evaluation is {ev.status}.'}, status=400)

        item = get_object_or_404(DatasetItem, pk=item_id, dataset=ev.dataset)
        notes = request.data.get('notes', '')
        acc   = request.data.get('accepted_value', '')
        Review.objects.update_or_create(
            evaluation=ev, item=item, reviewer=request.user,
            defaults={'notes': notes, 'accepted_value': acc},
        )
        _notify(
            request.user,
            kind='points',
            title='+8 points for reviewing',
            body=f'Your review in "{ev.name}" was recorded.',
            actor=request.user,
            evaluation=ev,
            data={'points': 8, 'activity': 'review', 'evaluation_id': ev.id},
        )
        _notify_evaluation_members(
            ev,
            kind='activity',
            title='New review submitted',
            body=f'{request.user.username} submitted a review in "{ev.name}".',
            actor=request.user,
            data={'activity': 'review', 'evaluation_id': ev.id, 'item_id': item.id},
        )
        return Response({'ok': True})


@api_view(['GET', 'POST'])
@permission_classes([IsAuthenticated])
def evaluation_chat(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)
    if request.method == 'GET':
        limit = min(max(int(request.query_params.get('limit', 80)), 1), 200)
        qs = ev.messages.select_related('author', 'author__profile').order_by('-created_at')[:limit]
        return Response(
            EvaluationMessageSerializer(
                reversed(list(qs)),
                many=True,
                context={'request': request},
            ).data
        )

    body = str(request.data.get('body', '')).strip()
    if not body:
        return Response({'detail': 'body is required.'}, status=400)
    if len(body) > 2000:
        return Response({'detail': 'body must be 2000 characters or fewer.'}, status=400)
    msg = EvaluationMessage.objects.create(evaluation=ev, author=request.user, body=body)
    _notify_evaluation_members(
        ev,
        kind='chat',
        title='New chat message',
        body=f'{request.user.username} sent a message in "{ev.name}".',
        actor=request.user,
        data={'activity': 'chat', 'evaluation_id': ev.id, 'message_id': msg.id},
    )
    return Response(EvaluationMessageSerializer(msg, context={'request': request}).data, status=201)


# ---------------------------------------------------------------------------
# Phase 6 — Metrics & results
# ---------------------------------------------------------------------------
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def evaluation_metrics(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)

    judgs = Judgment.objects.filter(evaluation=ev)
    by_item = {}
    for j in judgs:
        by_item.setdefault(j.item_id, {})[j.judge_id] = j.value

    judge_ids  = sorted({j.judge_id for j in judgs})
    shared_iids = [iid for iid, d in by_item.items() if len(d) >= 2]

    def cohen_kappa(l1, l2):
        if not l1:
            return None
        cats = sorted(set(l1) | set(l2))
        idx  = {c: i for i, c in enumerate(cats)}
        M    = np.zeros((len(cats), len(cats)), dtype=int)
        for a, b in zip(l1, l2):
            M[idx[a], idx[b]] += 1
        total = M.sum()
        if total == 0:
            return None
        po = np.trace(M) / total
        pi = (M.sum(axis=0) / total) @ (M.sum(axis=1) / total)
        return 1.0 if pi == 1.0 else float((po - pi) / (1 - pi))

    pairs = []
    for i in range(len(judge_ids)):
        for j in range(i + 1, len(judge_ids)):
            a, b = judge_ids[i], judge_ids[j]
            l1 = [by_item[iid][a] for iid in shared_iids if a in by_item[iid] and b in by_item[iid]]
            l2 = [by_item[iid][b] for iid in shared_iids if a in by_item[iid] and b in by_item[iid]]
            pairs.append({'judges': [a, b], 'cohen_kappa': cohen_kappa(l1, l2)})

    # Per-label statistics
    all_labels = [j.value for j in judgs]
    label_counts = dict(Counter(all_labels))
    total = len(all_labels)
    per_label = {
        lbl: {
            'count': cnt,
            'pct': round(cnt / total * 100, 1) if total else 0,
        }
        for lbl, cnt in sorted(label_counts.items(), key=lambda x: -x[1])
    }

    return Response({
        'judge_ids': judge_ids,
        'pairs': pairs,
        'items_used': len(shared_iids),
        'total_judgments': total,
        'per_label': per_label,
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def evaluation_results(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)

    judgs   = Judgment.objects.filter(evaluation=ev)
    by_item = {}
    for j in judgs:
        by_item.setdefault(j.item_id, []).append(j.value)

    out = []
    for iid, labels in by_item.items():
        c       = Counter(labels)
        majority = c.most_common(1)[0][0]
        out.append({
            'item_id':  iid,
            'majority': majority,
            'counts':   dict(c),
            'n_judges': len(labels),
            'unanimous': len(c) == 1,
        })
    return Response({'results': out})


# ---------------------------------------------------------------------------
# Phase 7 — Export & closure
# ---------------------------------------------------------------------------
@api_view(['GET'])
@permission_classes([IsAuthenticated])
def export_results_csv(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)

    judgs = Judgment.objects.filter(evaluation=ev).select_related('judge')
    rows  = [['item_id', 'judge_id', 'judge_username', 'label', 'confidence', 'created_at']]
    for j in judgs:
        rows.append([
            j.item_id, j.judge_id, j.judge.username,
            j.value,
            j.confidence if j.confidence is not None else '',
            j.created_at.isoformat(),
        ])
    report = ev.threat_reports.first()
    if report:
        rows.append([])
        rows.append(['llm_threats_to_validity_non_human'])
        rows.append(['report_json', json.dumps(report.report, default=_json_default)])
        rows.append(['model', report.llm_run.model_name if report.llm_run else ''])
        rows.append(['prompt_version', report.llm_run.prompt_version if report.llm_run else ''])
    buf = io.StringIO()
    csv.writer(buf).writerows(rows)
    resp = HttpResponse(buf.getvalue(), content_type='text/csv')
    resp['Content-Disposition'] = f'attachment; filename="evaluation_{ev.id}_judgments.csv"'
    return resp


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def export_results_json(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)

    judgs = Judgment.objects.filter(evaluation=ev).select_related('judge')
    data  = [
        {
            'item_id':   j.item_id,
            'judge_id':  j.judge_id,
            'judge':     j.judge.username,
            'label':     j.value,
            'confidence': j.confidence,
            'created_at': j.created_at.isoformat(),
        }
        for j in judgs
    ]
    report = ev.threat_reports.first()
    return Response({
        'evaluation': ev.id,
        'status': ev.status,
        'judgments': data,
        'llm_threats_to_validity': ThreatsValidityReportSerializer(report).data if report else None,
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def platform_rankings(request):
    limit = int(request.query_params.get('limit', 50))
    return Response({
        'scope': 'platform',
        'rankings': platform_ranking(limit=min(max(limit, 1), 100)),
    })


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def evaluation_rankings(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)
    return Response(evaluation_ranking(ev))


def _validity_stats_snapshot(ev):
    label_counts = Counter(ev.judgments.values_list('value', flat=True))
    by_judge = Counter(ev.judgments.values_list('judge_id', flat=True))
    by_item = defaultdict(set)
    for item_id, value in ev.judgments.values_list('item_id', 'value'):
        by_item[item_id].add(value)
    disputed = sum(1 for labels in by_item.values() if len(labels) > 1)
    total_judged_items = len(by_item)
    return {
        'evaluation_id': ev.id,
        'status': ev.status,
        'n_items': ev.dataset.items.count(),
        'n_judges': ev.judges.count(),
        'n_reviewers': ev.reviewers.count(),
        'n_judgments': ev.judgments.count(),
        'n_reviews': ev.reviews.count(),
        'class_distribution': dict(label_counts),
        'items_per_judge': {str(k): v for k, v in by_judge.items()},
        'disagreement_rate': round(disputed / total_judged_items, 3) if total_judged_items else 0,
        'low_activity_judges': [
            judge_id for judge_id in ev.judges.values_list('pk', flat=True)
            if by_judge[judge_id] < max(1, total_judged_items // 4)
        ],
        'published_codebook': bool(_published_codebook(ev)),
    }


def _generate_threat_report(ev, user):
    existing = ev.threat_reports.first()
    if existing:
        return existing
    stats = _validity_stats_snapshot(ev)
    prompt = (
        "You are writing a threats-to-validity section for a completed labeling study. "
        "Interpret only these aggregate statistics. Do not inspect raw item text and do not "
        "create or imply labels. Discuss class imbalance, low per-label reliability where visible, "
        "judge workload imbalance, disagreement rate, and possible anchoring signals.\n\n"
        f"Final statistics:\n{json.dumps(stats, indent=2, default=_json_default)}\n\n"
        "Return JSON with keys: executive_summary, construct_validity, internal_validity, "
        "external_validity, conclusion."
    )
    result = llm_call(prompt, prompt_version='threats-validity-freeze-v2')
    run = _store_llm_run(
        feature='threats_validity',
        prompt=prompt,
        prompt_version='threats-validity-freeze-v2',
        result=result,
        user=user,
        evaluation=ev,
        input_payload=stats,
    )
    report = run.output_json
    if not isinstance(report, dict) or not report:
        report = {
            'executive_summary': 'No structured report was returned.',
            'construct_validity': [],
            'internal_validity': [],
            'external_validity': [],
            'conclusion': '',
        }
    markdown = '\n\n'.join([
        '# Threats to Validity',
        str(report.get('executive_summary', '')),
        '## Conclusion',
        str(report.get('conclusion', '')),
    ])
    return ThreatsValidityReport.objects.create(
        evaluation=ev,
        llm_run=run,
        stats_snapshot=stats,
        report=report,
        markdown=markdown,
        created_by=user,
    )


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def threat_report(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)
    report = ev.threat_reports.first()
    return Response(ThreatsValidityReportSerializer(report).data if report else {})


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def close_evaluation(request, eval_id):
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if ev.owner_id != request.user.pk:
        return Response({'detail': 'Only the owner can close the evaluation.'}, status=403)
    if ev.status in ('closed', 'frozen', 'archived'):
        return Response({'detail': f'Already {ev.status}.'}, status=400)
    ev.status = 'closed'
    ev.save(update_fields=['status'])
    report = _generate_threat_report(ev, request.user)
    _notify_evaluation_members(
        ev,
        kind='evaluation',
        title='Evaluation closed',
        body=f'"{ev.name}" was closed by {request.user.username}.',
        actor=request.user,
        data={'activity': 'closed', 'evaluation_id': ev.id},
        include_actor=True,
    )
    return Response({
        'ok': True,
        'status': ev.status,
        'threat_report': ThreatsValidityReportSerializer(report).data,
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def freeze_evaluation(request, eval_id):
    """Freeze: no more judgments or reviews; triggers threats-to-validity in Phase 8."""
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if ev.owner_id != request.user.pk:
        return Response({'detail': 'Only the owner can freeze the evaluation.'}, status=403)
    if ev.status == 'frozen':
        return Response({'detail': 'Already frozen.'}, status=400)
    ev.status = 'frozen'
    ev.save(update_fields=['status'])
    report = _generate_threat_report(ev, request.user)
    _notify_evaluation_members(
        ev,
        kind='evaluation',
        title='Evaluation frozen',
        body=f'"{ev.name}" was frozen by {request.user.username}.',
        actor=request.user,
        data={'activity': 'frozen', 'evaluation_id': ev.id},
        include_actor=True,
    )
    return Response({
        'ok': True,
        'status': ev.status,
        'threat_report': ThreatsValidityReportSerializer(report).data,
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def open_evaluation(request, eval_id):
    """Move an evaluation from draft → open (accepts judgments)."""
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if ev.owner_id != request.user.pk:
        return Response({'detail': 'Only the owner can open the evaluation.'}, status=403)
    if ev.status != 'draft':
        return Response({'detail': 'Only draft evaluations can be opened.'}, status=400)
    ev.status = 'open'
    ev.save(update_fields=['status'])
    _notify_evaluation_members(
        ev,
        kind='evaluation',
        title='Evaluation opened',
        body=f'"{ev.name}" is now open for work.',
        actor=request.user,
        data={'activity': 'opened', 'evaluation_id': ev.id},
        include_actor=True,
    )
    return Response({'ok': True, 'status': ev.status})


# ---------------------------------------------------------------------------
# Legacy — removed; returns 410 Gone (violated Phase 8 non-anchoring rule)
# ---------------------------------------------------------------------------
@api_view(['POST'])
@permission_classes([IsAuthenticated])
def ai_suggest(request):
    return Response(
        {'detail': 'Endpoint removed. LLM features are meta-evaluation only (Phase 8).'},
        status=410,
    )


# ---------------------------------------------------------------------------
# Phase 8 — LLM meta-evaluation endpoints
#
# Safety invariants (enforced here):
#   1. No endpoint writes to Judgment or Review.
#   2. Only aggregated/anonymised data is sent to the LLM.
#   3. Every response includes llm_meta with provider/model/prompt_version.
#   4. All endpoints require at least member-level access to the evaluation.
# ---------------------------------------------------------------------------
from .meta_eval import (                                         # noqa: E402
    disagreement_diagnosis,
    effort_estimation,
    intra_judge_consistency,
    codebook_induction,
    threats_to_validity,
    semantic_label_normalisation,
)


def _meta_eval_judgments(ev: Evaluation) -> list[dict]:
    """Return aggregated judgment data safe to pass to LLM (no item text)."""
    return [
        {
            'item_id':    j.item_id,
            'judge_id':   j.judge_id,
            'label':      j.value,
            'confidence': j.confidence,
            'created_at': j.created_at.isoformat(),
            # bucket: use dataset item's row_index as a neutral proxy
            'bucket':     str(j.item.row_index % 10),  # coarse decile bucket
        }
        for j in ev.judgments.all().select_related('item')
    ]


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def meta_disagreement(request, eval_id):
    """Feature 1 — Disagreement diagnosis."""
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)
    judgments = _meta_eval_judgments(ev)
    return Response(disagreement_diagnosis(judgments))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def meta_effort(request, eval_id):
    """Feature 2 — Effort estimation."""
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)
    judgments = _meta_eval_judgments(ev)
    return Response(effort_estimation(judgments))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def meta_consistency(request, eval_id):
    """Feature 3 — Intra-judge consistency audit."""
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)
    judgments = _meta_eval_judgments(ev)
    return Response(intra_judge_consistency(judgments))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def meta_codebook(request, eval_id):
    """Feature 4 — Codebook induction from label distribution."""
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)
    from collections import Counter
    labels = list(ev.judgments.values_list('value', flat=True))
    counts = dict(Counter(labels))
    return Response(codebook_induction(counts))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def meta_validity(request, eval_id):
    """Feature 5 — Threats-to-validity report."""
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)

    # Compute study summary (aggregated — no item text)
    from itertools import combinations as _combinations
    judge_ids = list(ev.judges.values_list('pk', flat=True))
    pair_kappas = []
    for ja, jb in _combinations(judge_ids, 2):
        ja_judgs = {j.item_id: j.value for j in ev.judgments.filter(judge_id=ja)}
        jb_judgs = {j.item_id: j.value for j in ev.judgments.filter(judge_id=jb)}
        common   = set(ja_judgs) & set(jb_judgs)
        if len(common) >= 2:
            ya = [ja_judgs[i] for i in common]
            yb = [jb_judgs[i] for i in common]
            all_labels = sorted(set(ya) | set(yb))
            ya_idx = [all_labels.index(v) for v in ya]
            yb_idx = [all_labels.index(v) for v in yb]
            try:
                kappa = float(np.corrcoef(ya_idx, yb_idx)[0, 1])
            except Exception:
                kappa = None
            pair_kappas.append(kappa)

    summary = {
        'eval_id':      ev.id,
        'status':       ev.status,
        'n_judges':     ev.judges.count(),
        'n_reviewers':  ev.reviewers.count(),
        'n_items':      ev.dataset.items.count(),
        'n_judgments':  ev.judgments.count(),
        'n_reviews':    ev.reviews.count(),
        'mean_kappa':   round(float(np.mean(pair_kappas)), 3)
                        if pair_kappas else None,
        'min_kappa':    round(float(np.min(pair_kappas)), 3)
                        if pair_kappas else None,
    }
    return Response(threats_to_validity(summary))


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def meta_normalise(request, eval_id):
    """Feature 6 — Semantic label normalisation."""
    ev = get_object_or_404(Evaluation, pk=eval_id)
    if get_eval_role(request.user, ev) is None:
        return Response({'detail': 'Not a member.'}, status=403)
    labels = list(ev.judgments.values_list('value', flat=True))
    return Response(semantic_label_normalisation(labels))

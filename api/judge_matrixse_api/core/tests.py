"""
JudgeMatrixSE — backend test suite.
Run with:  cd api && python3 manage.py test core -v 2
"""
import io as _io, json as _json
import importlib
import tempfile
from pathlib import Path
from unittest import mock
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import clear_url_caches
from django.contrib.auth.models import User
from rest_framework.test import APIClient
from .models import (
    Codebook, UserProfile, Dataset, DatasetItem, Evaluation,
    DisagreementDiagnosis, EvaluationMessage, Judgment, LabelNormalizationProposal,
    LLMRun, Notification, Review, RoutingSuggestion, ConsistencyFinding, ThreatsValidityReport,
    UserFollow,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
CSV = 'id,text,label\n1,hello,bug\n2,world,feature\n'


def make_user(username='alice', password='pass1234'):
    return User.objects.create_user(username=username, password=password)


def get_token(client, username, password='pass1234'):
    r = client.post('/api/auth/token/', {'username': username, 'password': password}, format='json')
    return r.data['access']


def auth(client, token):
    client.credentials(HTTP_AUTHORIZATION=f'Bearer {token}')


def upload_csv(client, name='ds', csv_text=CSV):
    return client.post(
        '/api/datasets/upload-csv/',
        {'file': _io.BytesIO(csv_text.encode()),
         'meta': _json.dumps({'delimiter': ',', 'encoding': 'UTF-8', 'dataset_name': name})},
        format='multipart',
    )


def create_eval(client, ds_id, name='E', judges=None, reviewers=None, viewers=None):
    body = {'name': name, 'dataset': ds_id}
    if judges:    body['judges']    = judges
    if reviewers: body['reviewers'] = reviewers
    if viewers:   body['viewers']   = viewers
    return client.post('/api/evaluations/', body, format='json')


class LLMProviderTests(TestCase):
    def test_deepseek_provider_uses_deepseek_dispatcher(self):
        from . import llm_service

        with (
            mock.patch.object(llm_service, 'LLM_PROVIDER', 'deepseek'),
            mock.patch.object(llm_service, 'LLM_MODEL', 'deepseek-v4-flash'),
            mock.patch.object(
                llm_service,
                '_call_deepseek',
                return_value=('{"ok": true}', {'provider': 'deepseek'}),
            ) as call_deepseek,
        ):
            result = llm_service.call('hello', prompt_version='deepseek-test-v1')

        call_deepseek.assert_called_once()
        self.assertEqual(result.provider, 'deepseek')
        self.assertEqual(result.model, 'deepseek-v4-flash')
        self.assertEqual(result.text, '{"ok": true}')


# ---------------------------------------------------------------------------
# Phase 0 — Auth
# ---------------------------------------------------------------------------
class RegisterTests(TestCase):
    def setUp(self): self.c = APIClient()

    def test_register_creates_user_and_profile(self):
        r = self.c.post('/api/auth/register/', {'username': 'bob', 'password': 'secret99'}, format='json')
        self.assertEqual(r.status_code, 201)
        self.assertTrue(UserProfile.objects.filter(user__username='bob').exists())

    def test_register_duplicate_username(self):
        make_user('bob')
        r = self.c.post('/api/auth/register/', {'username': 'bob', 'password': 'pass'}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_register_missing_fields(self):
        r = self.c.post('/api/auth/register/', {'username': 'bob'}, format='json')
        self.assertEqual(r.status_code, 400)


class LoginTests(TestCase):
    def setUp(self):
        self.c = APIClient()
        make_user('alice')

    def test_login_returns_tokens(self):
        r = self.c.post('/api/auth/token/', {'username': 'alice', 'password': 'pass1234'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertIn('access', r.data); self.assertIn('refresh', r.data)

    def test_login_wrong_password(self):
        r = self.c.post('/api/auth/token/', {'username': 'alice', 'password': 'wrong'}, format='json')
        self.assertEqual(r.status_code, 401)

    def test_token_refresh(self):
        r  = self.c.post('/api/auth/token/', {'username': 'alice', 'password': 'pass1234'}, format='json')
        r2 = self.c.post('/api/auth/token/refresh/', {'refresh': r.data['refresh']}, format='json')
        self.assertEqual(r2.status_code, 200)
        self.assertIn('access', r2.data)


class MeTests(TestCase):
    def setUp(self):
        self.c = APIClient()
        make_user('alice')
        auth(self.c, get_token(self.c, 'alice'))

    def test_get_me(self):
        r = self.c.get('/api/auth/me/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data['username'], 'alice')

    def test_me_requires_auth(self):
        r = APIClient().get('/api/auth/me/')
        self.assertEqual(r.status_code, 401)


class UserSearchTests(TestCase):
    def setUp(self):
        self.c = APIClient()
        make_user('alice'); make_user('bob'); make_user('charlie')
        auth(self.c, get_token(self.c, 'alice'))

    def test_search_returns_others(self):
        r = self.c.get('/api/users/?search=bob')
        self.assertEqual(r.status_code, 200)
        names = [u['username'] for u in r.data]
        self.assertIn('bob', names)
        self.assertNotIn('alice', names)  # caller excluded

    def test_search_empty_returns_all_others(self):
        r = self.c.get('/api/users/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data), 2)

    def test_requires_auth(self):
        r = APIClient().get('/api/users/?search=bob')
        self.assertEqual(r.status_code, 401)


class ProtectedEndpointTests(TestCase):
    def setUp(self): self.c = APIClient()

    def test_health_is_public(self):
        r = self.c.get('/api/health/')
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data['ok'])

    def test_evaluations_requires_auth(self):
        self.assertEqual(self.c.get('/api/evaluations/').status_code, 401)

    def test_datasets_requires_auth(self):
        self.assertEqual(self.c.get('/api/datasets/').status_code, 401)


class ProductionMediaServingTests(TestCase):
    def test_media_is_served_when_enabled_outside_debug(self):
        with tempfile.TemporaryDirectory() as tmp:
            media_root = Path(tmp)
            avatars = media_root / 'avatars'
            avatars.mkdir()
            (avatars / 'avatar.txt').write_text('ok', encoding='utf-8')

            with override_settings(DEBUG=False, SERVE_MEDIA=True, MEDIA_ROOT=media_root):
                import judge_matrixse_api.urls as urlconf
                importlib.reload(urlconf)
                clear_url_caches()
                try:
                    r = self.client.get('/media/avatars/avatar.txt')
                    self.assertEqual(r.status_code, 200)
                    self.assertEqual(b''.join(r.streaming_content), b'ok')
                finally:
                    importlib.reload(urlconf)
                    clear_url_caches()


# ---------------------------------------------------------------------------
# Phase 2 — Dataset upload
# ---------------------------------------------------------------------------
class DatasetUploadTests(TestCase):
    def setUp(self):
        self.c = APIClient()
        make_user('alice')
        auth(self.c, get_token(self.c, 'alice'))

    def test_upload_csv_creates_items(self):
        r = upload_csv(self.c)
        self.assertEqual(r.status_code, 200)
        self.assertIn('dataset_id', r.data)
        self.assertEqual(DatasetItem.objects.filter(dataset_id=r.data['dataset_id']).count(), 2)

    def test_upload_requires_auth(self):
        r = APIClient().post('/api/datasets/upload-csv/', {
            'file': _io.BytesIO(CSV.encode()),
            'meta': _json.dumps({'delimiter': ',', 'encoding': 'UTF-8', 'dataset_name': 'x'}),
        }, format='multipart')
        self.assertEqual(r.status_code, 401)

    def test_label_normalization_creates_traceable_proposal(self):
        r = upload_csv(self.c, csv_text='id,text,label\n1,a,bug\n2,b,defect\n3,c,feature\n')
        ds_id = r.data['dataset_id']
        self.c.post(
            f'/api/datasets/{ds_id}/versions/{r.data["version"]}/mapping/',
            {'columns': [
                {'name_in_file': 'id', 'mapped_name': 'id', 'role': 'ID'},
                {'name_in_file': 'text', 'mapped_name': 'text', 'role': 'TEXT'},
                {'name_in_file': 'label', 'mapped_name': 'label', 'role': 'LABEL'},
            ]},
            format='json',
        )
        res = self.c.post(
            f'/api/datasets/{ds_id}/llm/label-normalization/',
            {'label_column': 'label'},
            format='json',
        )
        self.assertEqual(res.status_code, 201, msg=res.data)
        self.assertEqual(LLMRun.objects.filter(feature='label_normalization').count(), 1)
        self.assertEqual(LabelNormalizationProposal.objects.count(), 1)
        self.assertIn('proposed_mapping', res.data)

    def test_label_normalization_approval_applies_mapping(self):
        r = upload_csv(self.c, csv_text='id,text,label\n1,a,bug\n2,b,defect\n')
        ds_id = r.data['dataset_id']
        self.c.post(
            f'/api/datasets/{ds_id}/versions/{r.data["version"]}/mapping/',
            {'columns': [
                {'name_in_file': 'id', 'mapped_name': 'id', 'role': 'ID'},
                {'name_in_file': 'text', 'mapped_name': 'text', 'role': 'TEXT'},
                {'name_in_file': 'label', 'mapped_name': 'label', 'role': 'LABEL'},
            ]},
            format='json',
        )
        gen = self.c.post(
            f'/api/datasets/{ds_id}/llm/label-normalization/',
            {'label_column': 'label'},
            format='json',
        )
        proposal_id = gen.data['id']
        res = self.c.patch(
            f'/api/llm/label-normalization/{proposal_id}/',
            {'status': 'approved', 'mapping': {'bug': 'bug', 'defect': 'bug'}},
            format='json',
        )
        self.assertEqual(res.status_code, 200, msg=res.data)
        self.assertEqual(res.data['items_changed'], 1)
        labels = list(DatasetItem.objects.filter(dataset_id=ds_id).values_list('data', flat=True))
        self.assertEqual([row['label'] for row in labels], ['bug', 'bug'])


# ---------------------------------------------------------------------------
# Phase 1 — Role permission enforcement
# ---------------------------------------------------------------------------
class RolePermissionSetup(TestCase):
    """Base class: creates owner, judge, reviewer, viewer, outsider + an eval."""
    def setUp(self):
        self.owner_c    = APIClient()
        self.judge_c    = APIClient()
        self.reviewer_c = APIClient()
        self.viewer_c   = APIClient()
        self.outsider_c = APIClient()

        self.owner    = make_user('owner')
        self.judge    = make_user('judge')
        self.reviewer = make_user('reviewer')
        self.viewer   = make_user('viewer')
        self.outsider = make_user('outsider')

        auth(self.owner_c,    get_token(self.owner_c,    'owner'))
        auth(self.judge_c,    get_token(self.judge_c,    'judge'))
        auth(self.reviewer_c, get_token(self.reviewer_c, 'reviewer'))
        auth(self.viewer_c,   get_token(self.viewer_c,   'viewer'))
        auth(self.outsider_c, get_token(self.outsider_c, 'outsider'))

        # Upload dataset as owner
        r = upload_csv(self.owner_c)
        self.ds_id = r.data['dataset_id']

        # Create evaluation with all roles
        r2 = create_eval(
            self.owner_c, self.ds_id,
            judges=[self.judge.pk],
            reviewers=[self.reviewer.pk],
            viewers=[self.viewer.pk],
        )
        self.eval_id = r2.data['id']
        self.item_id = DatasetItem.objects.filter(dataset_id=self.ds_id).first().pk


class JudgmentPermissionTests(RolePermissionSetup):
    def test_evaluation_members_can_read_dataset_metadata(self):
        for client in (self.judge_c, self.reviewer_c, self.viewer_c):
            with self.subTest(client=client):
                r = client.get(f'/api/datasets/{self.ds_id}/')
                self.assertEqual(r.status_code, 200)
                self.assertEqual(r.data['id'], self.ds_id)

    def test_outsider_cannot_read_dataset_metadata(self):
        r = self.outsider_c.get(f'/api/datasets/{self.ds_id}/')
        self.assertEqual(r.status_code, 404)

    def test_judge_can_submit(self):
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug', 'confidence': 0.9}, format='json')
        self.assertEqual(r.status_code, 200)
        judgment = Judgment.objects.get(evaluation_id=self.eval_id, item_id=self.item_id, judge=self.judge)
        self.assertEqual(judgment.labels, ['bug'])

    def test_items_include_current_user_progress(self):
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        r = self.judge_c.get(f'/api/evaluations/{self.eval_id}/items/')
        self.assertEqual(r.status_code, 200)
        first = next(row for row in r.data['results'] if row['id'] == self.item_id)
        self.assertEqual(r.data['completed_count'], 1)
        self.assertEqual(first['current_user_status'], 'labeled')
        self.assertEqual(first['current_user_judgment']['labels'], ['bug'])

    def test_single_label_eval_rejects_multiple_labels(self):
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'labels': ['bug', 'enhancement']}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_multi_label_eval_accepts_multiple_labels(self):
        Evaluation.objects.filter(pk=self.eval_id).update(allow_multiple_labels=True)
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'labels': ['bug', 'enhancement'], 'confidence': 0.7}, format='json')
        self.assertEqual(r.status_code, 200, msg=r.data)
        judgment = Judgment.objects.get(evaluation_id=self.eval_id, item_id=self.item_id, judge=self.judge)
        self.assertEqual(judgment.labels, ['bug', 'enhancement'])
        self.assertEqual(judgment.value, 'bug, enhancement')

    def test_owner_can_update_labeling_configuration(self):
        r = self.owner_c.patch(
            f'/api/evaluations/{self.eval_id}/',
            {
                'labeling_instructions': 'Use short GitHub issue categories.',
                'allow_multiple_labels': True,
            },
            format='json',
        )
        self.assertEqual(r.status_code, 200, msg=r.data)
        self.assertEqual(r.data['labeling_instructions'], 'Use short GitHub issue categories.')
        self.assertTrue(r.data['allow_multiple_labels'])

    def test_owner_can_delete_evaluation(self):
        r = self.owner_c.delete(f'/api/evaluations/{self.eval_id}/')
        self.assertEqual(r.status_code, 204)
        self.assertFalse(Evaluation.objects.filter(pk=self.eval_id).exists())

    def test_non_owner_cannot_delete_evaluation(self):
        r = self.judge_c.delete(f'/api/evaluations/{self.eval_id}/')
        self.assertEqual(r.status_code, 403)
        self.assertTrue(Evaluation.objects.filter(pk=self.eval_id).exists())

    def test_owner_can_judge(self):
        r = self.owner_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'feature'}, format='json')
        self.assertEqual(r.status_code, 200)

    def test_reviewer_cannot_judge(self):
        r = self.reviewer_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        self.assertEqual(r.status_code, 403)

    def test_viewer_cannot_judge(self):
        r = self.viewer_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        self.assertEqual(r.status_code, 403)

    def test_outsider_cannot_judge(self):
        r = self.outsider_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        self.assertEqual(r.status_code, 403)

    def test_judgment_requires_value(self):
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': ''}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_get_judgments_visible_to_members(self):
        # First submit one
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        # Reviewer (non-judge) can read
        r = self.reviewer_c.get(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data), 1)

    def test_get_judgments_blocked_for_outsider(self):
        r = self.outsider_c.get(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/')
        self.assertEqual(r.status_code, 403)


class CodebookWorkflowTests(RolePermissionSetup):
    def setUp(self):
        super().setUp()
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug', 'confidence': 0.9},
            format='json',
        )

    def test_owner_can_generate_codebook_draft(self):
        r = self.owner_c.post(
            f'/api/evaluations/{self.eval_id}/codebooks/',
            {'force': True},
            format='json',
        )
        self.assertEqual(r.status_code, 201, msg=r.data)
        self.assertEqual(Codebook.objects.count(), 1)
        self.assertEqual(LLMRun.objects.filter(feature='codebook_induction').count(), 1)
        self.assertEqual(r.data['status'], 'draft')

    def test_only_owner_can_generate_codebook(self):
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/codebooks/',
            {'force': True},
            format='json',
        )
        self.assertEqual(r.status_code, 403)

    def test_published_codebook_visible_to_judge(self):
        gen = self.owner_c.post(
            f'/api/evaluations/{self.eval_id}/codebooks/',
            {'force': True},
            format='json',
        )
        codebook_id = gen.data['id']
        pub = self.owner_c.patch(
            f'/api/codebooks/{codebook_id}/',
            {'status': 'published', 'markdown': '## Bug\nOperational definition.'},
            format='json',
        )
        self.assertEqual(pub.status_code, 200, msg=pub.data)
        r = self.judge_c.get(f'/api/evaluations/{self.eval_id}/codebooks/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data), 1)
        self.assertEqual(r.data[0]['status'], 'published')


class ConsistencyAuditTests(RolePermissionSetup):
    def setUp(self):
        super().setUp()
        items = list(DatasetItem.objects.filter(dataset_id=self.ds_id).order_by('row_index'))
        self.item_a = items[0]
        self.item_b = items[1]
        self.item_b.data['text'] = 'hello again'
        self.item_b.save(update_fields=['data'])
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_a.pk}/judgments/',
            {'value': 'bug'},
            format='json',
        )
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_b.pk}/judgments/',
            {'value': 'feature'},
            format='json',
        )

    def test_reviewer_can_run_consistency_audit(self):
        r = self.reviewer_c.post(
            f'/api/evaluations/{self.eval_id}/llm/consistency/?judge_id={self.judge.pk}')
        self.assertEqual(r.status_code, 201, msg=r.data)
        self.assertEqual(ConsistencyFinding.objects.count(), 1)
        self.assertEqual(LLMRun.objects.filter(feature='consistency_audit').count(), 1)

    def test_finding_can_be_marked_genuinely_different(self):
        gen = self.reviewer_c.post(
            f'/api/evaluations/{self.eval_id}/llm/consistency/?judge_id={self.judge.pk}')
        finding_id = gen.data[0]['id']
        r = self.reviewer_c.patch(
            f'/api/llm/consistency/{finding_id}/',
            {'status': 'genuinely_different', 'feedback': 'Different contexts.'},
            format='json',
        )
        self.assertEqual(r.status_code, 200, msg=r.data)
        self.assertEqual(r.data['status'], 'genuinely_different')

    def test_viewer_cannot_run_consistency_audit(self):
        r = self.viewer_c.post(
            f'/api/evaluations/{self.eval_id}/llm/consistency/?judge_id={self.judge.pk}')
        self.assertEqual(r.status_code, 403)


class ReviewPermissionTests(RolePermissionSetup):
    def test_reviewer_can_submit(self):
        r = self.reviewer_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/reviews/',
            {'notes': 'wrong label', 'accepted_value': 'feature'}, format='json')
        self.assertEqual(r.status_code, 200)

    def test_owner_can_review(self):
        r = self.owner_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/reviews/',
            {'notes': 'ok'}, format='json')
        self.assertEqual(r.status_code, 200)

    def test_judge_cannot_review(self):
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/reviews/',
            {'notes': 'wrong'}, format='json')
        self.assertEqual(r.status_code, 403)

    def test_viewer_cannot_review(self):
        r = self.viewer_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/reviews/',
            {'notes': 'wrong'}, format='json')
        self.assertEqual(r.status_code, 403)

    def test_get_reviews_visible_to_judge(self):
        self.reviewer_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/reviews/',
            {'notes': 'check this'}, format='json')
        r = self.judge_c.get(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/reviews/')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(len(r.data), 1)

    def test_reviewer_can_diagnose_disagreement(self):
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        self.owner_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'feature'}, format='json')
        r = self.reviewer_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/llm/disagreement/')
        self.assertEqual(r.status_code, 201, msg=r.data)
        self.assertEqual(DisagreementDiagnosis.objects.count(), 1)
        self.assertEqual(LLMRun.objects.filter(feature='disagreement_diagnosis').count(), 1)

    def test_judge_cannot_diagnose_disagreement(self):
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/llm/disagreement/')
        self.assertEqual(r.status_code, 403)


class EvaluationChatTests(RolePermissionSetup):
    def test_member_can_post_and_read_chat(self):
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/chat/',
            {'body': 'I am unsure about item 2.'},
            format='json',
        )
        self.assertEqual(r.status_code, 201, msg=r.data)
        self.assertEqual(EvaluationMessage.objects.count(), 1)
        read = self.reviewer_c.get(f'/api/evaluations/{self.eval_id}/chat/')
        self.assertEqual(read.status_code, 200)
        self.assertEqual(read.data[0]['body'], 'I am unsure about item 2.')
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.reviewer,
                actor=self.judge,
                kind='chat',
                evaluation_id=self.eval_id,
            ).exists()
        )
        self.assertFalse(
            Notification.objects.filter(
                recipient=self.judge,
                actor=self.judge,
                kind='chat',
                evaluation_id=self.eval_id,
            ).exists()
        )


class PublicEvaluationNotificationTests(RolePermissionSetup):
    def test_owner_can_publish_and_outsider_can_join_public_evaluation(self):
        r = self.owner_c.patch(
            f'/api/evaluations/{self.eval_id}/',
            {'is_public': True, 'public_join_roles': ['judge', 'reviewer']},
            format='json',
        )
        self.assertEqual(r.status_code, 200, msg=r.data)
        self.assertTrue(r.data['is_public'])

        listing = self.outsider_c.get('/api/evaluations/public/')
        self.assertEqual(listing.status_code, 200)
        self.assertTrue(any(ev['id'] == self.eval_id for ev in listing.data))

        joined = self.outsider_c.post(
            f'/api/evaluations/{self.eval_id}/join/',
            {'role': 'judge'},
            format='json',
        )
        self.assertEqual(joined.status_code, 200, msg=joined.data)
        self.assertIn('judge', joined.data['my_roles'])
        self.assertTrue(
            Evaluation.objects.get(pk=self.eval_id).judges.filter(pk=self.outsider.pk).exists()
        )
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.owner,
                kind='activity',
                evaluation_id=self.eval_id,
            ).exists()
        )

    def test_public_profile_lists_only_public_evaluation_participation(self):
        private = Evaluation.objects.get(pk=self.eval_id)
        private.is_public = False
        private.save(update_fields=['is_public'])
        hidden = self.owner_c.get(f'/api/users/{self.judge.pk}/profile/')
        self.assertEqual(hidden.status_code, 200)
        self.assertEqual(hidden.data['public_evaluations'], [])

        private.is_public = True
        private.public_join_roles = ['judge']
        private.save(update_fields=['is_public', 'public_join_roles'])
        visible = self.owner_c.get(f'/api/users/{self.judge.pk}/profile/')
        self.assertEqual(visible.status_code, 200)
        self.assertEqual(visible.data['public_evaluations'][0]['id'], self.eval_id)
        self.assertIn('judge', visible.data['public_evaluations'][0]['roles'])

    def test_notifications_are_listed_and_marked_read(self):
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'},
            format='json',
        )
        r = self.judge_c.get('/api/notifications/')
        self.assertEqual(r.status_code, 200)
        self.assertGreaterEqual(r.data['unread'], 1)
        self.assertTrue(any(n['kind'] == 'points' for n in r.data['notifications']))

        read = self.judge_c.post('/api/notifications/read/', {}, format='json')
        self.assertEqual(read.status_code, 200)
        r2 = self.judge_c.get('/api/notifications/')
        self.assertEqual(r2.data['unread'], 0)

    def test_outsider_cannot_use_chat(self):
        r = self.outsider_c.post(
            f'/api/evaluations/{self.eval_id}/chat/',
            {'body': 'hello'},
            format='json',
        )
        self.assertEqual(r.status_code, 403)


class EvaluationOwnershipTests(RolePermissionSetup):
    def test_only_owner_can_close(self):
        r = self.judge_c.post(f'/api/evaluations/{self.eval_id}/close/')
        self.assertEqual(r.status_code, 403)

    def test_owner_can_close(self):
        r = self.owner_c.post(f'/api/evaluations/{self.eval_id}/close/')
        self.assertEqual(r.status_code, 200)

    def test_only_owner_can_freeze(self):
        r = self.reviewer_c.post(f'/api/evaluations/{self.eval_id}/freeze/')
        self.assertEqual(r.status_code, 403)

    def test_owner_can_freeze(self):
        r = self.owner_c.post(f'/api/evaluations/{self.eval_id}/freeze/')
        self.assertEqual(r.status_code, 200)
        self.assertIn('threat_report', r.data)
        self.assertEqual(ThreatsValidityReport.objects.count(), 1)
        self.assertEqual(LLMRun.objects.filter(feature='threats_validity').count(), 1)

    def test_no_judgment_on_frozen_eval(self):
        self.owner_c.post(f'/api/evaluations/{self.eval_id}/freeze/')
        r = self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        self.assertEqual(r.status_code, 400)

    def test_outsider_cannot_see_eval(self):
        r = self.outsider_c.get(f'/api/evaluations/{self.eval_id}/')
        self.assertEqual(r.status_code, 404)  # filtered queryset → 404

    def test_only_owner_can_patch_eval(self):
        r = self.judge_c.patch(f'/api/evaluations/{self.eval_id}/', {'name': 'hacked'}, format='json')
        self.assertEqual(r.status_code, 403)

    def test_owner_can_patch_eval(self):
        r = self.owner_c.patch(f'/api/evaluations/{self.eval_id}/', {'name': 'renamed'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data['name'], 'renamed')

    def test_owner_can_generate_effort_routing(self):
        r = self.owner_c.post(f'/api/evaluations/{self.eval_id}/llm/routing/')
        self.assertEqual(r.status_code, 201, msg=r.data)
        self.assertEqual(RoutingSuggestion.objects.count(), 1)
        self.assertEqual(LLMRun.objects.filter(feature='effort_routing').count(), 1)
        self.assertIn('item_scores', r.data)
        self.assertIn('summary', r.data)

    def test_only_owner_can_generate_effort_routing(self):
        r = self.judge_c.post(f'/api/evaluations/{self.eval_id}/llm/routing/')
        self.assertEqual(r.status_code, 403)

    def test_owner_can_accept_effort_routing(self):
        gen = self.owner_c.post(f'/api/evaluations/{self.eval_id}/llm/routing/')
        suggestion_id = gen.data['id']
        r = self.owner_c.patch(
            f'/api/llm/routing/{suggestion_id}/',
            {'status': 'accepted'},
            format='json',
        )
        self.assertEqual(r.status_code, 200, msg=r.data)
        self.assertEqual(r.data['status'], 'accepted')


class MetricsPermissionTests(RolePermissionSetup):
    def test_viewer_can_read_metrics(self):
        r = self.viewer_c.get(f'/api/evaluations/{self.eval_id}/metrics/')
        self.assertEqual(r.status_code, 200)

    def test_outsider_cannot_read_metrics(self):
        r = self.outsider_c.get(f'/api/evaluations/{self.eval_id}/metrics/')
        self.assertEqual(r.status_code, 403)

    def test_metrics_has_per_label(self):
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        r = self.owner_c.get(f'/api/evaluations/{self.eval_id}/metrics/')
        self.assertEqual(r.status_code, 200)
        self.assertIn('per_label', r.data)
        self.assertIn('bug', r.data['per_label'])


class ExportPermissionTests(RolePermissionSetup):
    def test_member_can_export_csv(self):
        r = self.viewer_c.get(f'/api/evaluations/{self.eval_id}/export/csv/')
        self.assertEqual(r.status_code, 200)

    def test_outsider_cannot_export(self):
        r = self.outsider_c.get(f'/api/evaluations/{self.eval_id}/export/csv/')
        self.assertEqual(r.status_code, 403)

    def test_json_export_includes_threat_report_after_freeze(self):
        self.owner_c.post(f'/api/evaluations/{self.eval_id}/freeze/')
        r = self.owner_c.get(f'/api/evaluations/{self.eval_id}/export/json/')
        self.assertEqual(r.status_code, 200)
        self.assertIn('llm_threats_to_validity', r.data)
        self.assertIsNotNone(r.data['llm_threats_to_validity'])


# ---------------------------------------------------------------------------
# Phase 8 — Meta-evaluation endpoint tests
# ---------------------------------------------------------------------------
class MetaEvalTests(RolePermissionSetup):
    """All 6 meta-eval endpoints: member can call, outsider gets 403."""

    ENDPOINTS = [
        'disagreement', 'effort', 'consistency',
        'codebook', 'validity', 'normalise',
    ]

    def _get(self, client, feature):
        return client.get(f'/api/evaluations/{self.eval_id}/meta/{feature}/')

    def test_member_can_call_all_features(self):
        # Submit one judgment so codebook/disagreement have data
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json',
        )
        for feature in self.ENDPOINTS:
            with self.subTest(feature=feature):
                r = self._get(self.owner_c, feature)
                self.assertEqual(r.status_code, 200, msg=f'{feature}: {r.data}')

    def test_outsider_blocked_on_all_features(self):
        for feature in self.ENDPOINTS:
            with self.subTest(feature=feature):
                r = self._get(self.outsider_c, feature)
                self.assertEqual(r.status_code, 403)

    def test_viewer_can_call_all_features(self):
        for feature in self.ENDPOINTS:
            with self.subTest(feature=feature):
                r = self._get(self.viewer_c, feature)
                self.assertEqual(r.status_code, 200)

    def test_response_contains_llm_meta(self):
        r = self._get(self.owner_c, 'disagreement')
        self.assertEqual(r.status_code, 200)
        # stub mode always returns llm_meta
        self.assertIn('llm_meta', r.data)
        if r.data['llm_meta']:
            self.assertIn('provider', r.data['llm_meta'])
            self.assertIn('model',    r.data['llm_meta'])


# ---------------------------------------------------------------------------
# Phase 9 — Tutorial seed command smoke test
# ---------------------------------------------------------------------------
class TutorialSeedTest(TestCase):
    def test_seed_command_runs(self):
        from django.core.management import call_command
        call_command('seed_tutorial', '--force', verbosity=0)
        from core.models import Evaluation
        self.assertTrue(
            Evaluation.objects.filter(name='Tutorial Evaluation').exists()
        )


# ---------------------------------------------------------------------------
# Profile + gamification tests
# ---------------------------------------------------------------------------
class ProfileGamificationTests(RolePermissionSetup):
    def test_profile_update_extended_fields(self):
        r = self.owner_c.patch('/api/auth/me/update/', {
            'first_name': 'Ada',
            'last_name': 'Lovelace',
            'gender': 'female',
            'profile_message': 'I label with rigor.',
            'orcid': '0000-0001-2345-6789',
            'linkedin_url': 'https://www.linkedin.com/in/example',
            'google_scholar_url': 'https://scholar.google.com/citations?user=x',
            'other_platform_url': 'https://dblp.org/pid/example',
        }, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertEqual(r.data['first_name'], 'Ada')
        self.assertIn('total_points', r.data)
        self.assertIn('badges', r.data)

    def test_profile_photo_upload(self):
        from PIL import Image
        img = Image.new('RGB', (2, 2), color='cyan')
        buf = _io.BytesIO()
        img.save(buf, format='PNG')
        upload = SimpleUploadedFile('avatar.png', buf.getvalue(), content_type='image/png')
        r = self.owner_c.patch('/api/auth/me/update/', {
            'display_name': 'Owner With Photo',
            'avatar': upload,
        }, format='multipart')
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data['avatar'])
        self.assertTrue(r.data['avatar'].startswith('http://testserver/media/avatars/'))
        self.assertIn('/media/avatars/', r.data['avatar'])

        me = self.owner_c.get('/api/auth/me/')
        self.assertEqual(me.status_code, 200)
        self.assertEqual(me.data['avatar'], r.data['avatar'])

    @override_settings(PUBLIC_API_BASE_URL='https://api.example.test')
    def test_profile_photo_uses_public_api_base_url(self):
        from PIL import Image
        img = Image.new('RGB', (2, 2), color='cyan')
        buf = _io.BytesIO()
        img.save(buf, format='PNG')
        upload = SimpleUploadedFile('avatar.png', buf.getvalue(), content_type='image/png')
        r = self.owner_c.patch('/api/auth/me/update/', {
            'avatar': upload,
        }, format='multipart')
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data['avatar'].startswith('https://api.example.test/media/avatars/'))

    def test_follow_unfollow_flow(self):
        r = self.owner_c.post('/api/friends/invite/', {
            'user_id': self.reviewer.pk,
        }, format='json')
        self.assertEqual(r.status_code, 201)
        self.assertEqual(UserFollow.objects.count(), 1)
        self.assertEqual(r.data['following']['username'], 'reviewer')
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.reviewer,
                actor=self.owner,
                kind='follow',
            ).exists()
        )

        rels = self.owner_c.get('/api/friends/')
        self.assertEqual(rels.status_code, 200)
        self.assertEqual(len(rels.data['following']), 1)

        r2 = self.owner_c.delete(f'/api/friends/{self.reviewer.pk}/unfollow/')
        self.assertEqual(r2.status_code, 200)
        self.assertEqual(UserFollow.objects.count(), 0)

    @mock.patch('core.views.urlopen')
    def test_orcid_sync_normalizes_full_url(self, mocked_urlopen):
        class _Response:
            def __enter__(self):
                return self

            def __exit__(self, *_args):
                return False

            def read(self):
                return _json.dumps({
                    'group': [{
                        'work-summary': [{
                            'title': {'title': {'value': 'A Labeling Study'}},
                            'publication-date': {'year': {'value': '2026'}},
                            'journal-title': {'value': 'SE Journal'},
                            'put-code': 123,
                        }]
                    }]
                }).encode('utf-8')

        mocked_urlopen.return_value = _Response()
        r = self.owner_c.post('/api/auth/me/publications/sync/', {
            'orcid': 'https://orcid.org/0000-0001-2345-6789',
        }, format='json')
        self.assertEqual(r.status_code, 200, msg=r.data)
        self.assertEqual(r.data['orcid'], '0000-0001-2345-6789')
        self.assertEqual(r.data['publications'][0]['title'], 'A Labeling Study')
        self.assertTrue(
            Notification.objects.filter(
                recipient=self.owner,
                kind='profile',
                title='ORCID publications synced',
            ).exists()
        )

    def test_platform_ranking_counts_activity(self):
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        r = self.owner_c.get('/api/rankings/platform/')
        self.assertEqual(r.status_code, 200)
        self.assertIn('rankings', r.data)
        self.assertTrue(any(row['username'] == 'judge' for row in r.data['rankings']))

    @override_settings(PUBLIC_API_BASE_URL='https://api.example.test')
    def test_platform_ranking_uses_public_avatar_url(self):
        from PIL import Image
        img = Image.new('RGB', (2, 2), color='cyan')
        buf = _io.BytesIO()
        img.save(buf, format='PNG')
        upload = SimpleUploadedFile('avatar.png', buf.getvalue(), content_type='image/png')
        self.owner_c.patch('/api/auth/me/update/', {'avatar': upload}, format='multipart')

        r = self.owner_c.get('/api/rankings/platform/')
        self.assertEqual(r.status_code, 200)
        owner = next(row for row in r.data['rankings'] if row['username'] == 'owner')
        self.assertTrue(owner['avatar'].startswith('https://api.example.test/media/avatars/'))

    def test_evaluation_rankings_are_member_gated(self):
        self.judge_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/judgments/',
            {'value': 'bug'}, format='json')
        self.reviewer_c.post(
            f'/api/evaluations/{self.eval_id}/items/{self.item_id}/reviews/',
            {'notes': 'Looks correct.'}, format='json')

        r = self.owner_c.get(f'/api/evaluations/{self.eval_id}/rankings/')
        self.assertEqual(r.status_code, 200)
        self.assertIn('judges', r.data)
        self.assertIn('evaluators', r.data)
        self.assertIn('total', r.data)

        blocked = self.outsider_c.get(f'/api/evaluations/{self.eval_id}/rankings/')
        self.assertEqual(blocked.status_code, 403)

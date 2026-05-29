from rest_framework import serializers
from django.conf import settings
from django.contrib.auth.models import User
from django.db import models
from .models import (
    Codebook, ConsistencyFinding, DisagreementDiagnosis,
    Dataset, DatasetColumn, DatasetItem, Evaluation, EvaluationMessage,
    FriendInvitation,
    Judgment, LabelNormalizationProposal, LLMRun, Review, RoutingSuggestion,
    Notification, ThreatsValidityReport, UserBadge, UserFollow, UserProfile,
)


# ---------------------------------------------------------------------------
# User / Profile
# ---------------------------------------------------------------------------
def _absolute_file_url(serializer, file_field):
    if not file_field:
        return None
    try:
        url = file_field.url
    except ValueError:
        return None
    if settings.PUBLIC_API_BASE_URL:
        return f"{settings.PUBLIC_API_BASE_URL}{url}"
    request = serializer.context.get('request')
    return request.build_absolute_uri(url) if request else url


class AbsoluteImageField(serializers.ImageField):
    def to_representation(self, value):
        return _absolute_file_url(self, value)


class UserProfileSerializer(serializers.ModelSerializer):
    avatar = AbsoluteImageField(required=False, allow_null=True)

    class Meta:
        model = UserProfile
        fields = [
            'display_name', 'first_name', 'last_name', 'gender', 'bio',
            'profile_message', 'avatar', 'orcid', 'linkedin_url',
            'google_scholar_url', 'other_platform_url', 'publications',
            'badges_ready',
        ]


class UserMiniSerializer(serializers.ModelSerializer):
    display_name = serializers.SerializerMethodField()
    avatar = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'display_name', 'avatar']

    def get_display_name(self, obj):
        try:
            dn = obj.profile.display_name
            return dn if dn else obj.username
        except UserProfile.DoesNotExist:
            return obj.username

    def get_avatar(self, obj):
        try:
            return _absolute_file_url(self, obj.profile.avatar)
        except UserProfile.DoesNotExist:
            return None


class UserSearchSerializer(serializers.ModelSerializer):
    display_name = serializers.SerializerMethodField()
    avatar = serializers.SerializerMethodField()
    is_following = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'username', 'email', 'display_name', 'avatar', 'is_following']

    def get_display_name(self, obj):
        try:
            dn = obj.profile.display_name
            return dn if dn else obj.username
        except UserProfile.DoesNotExist:
            return obj.username

    def get_avatar(self, obj):
        try:
            return _absolute_file_url(self, obj.profile.avatar)
        except UserProfile.DoesNotExist:
            return None

    def get_is_following(self, obj):
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return False
        return UserFollow.objects.filter(follower=request.user, following=obj).exists()


class UserProfileDetailSerializer(serializers.ModelSerializer):
    username   = serializers.CharField(source='user.username', read_only=True)
    email      = serializers.CharField(source='user.email',    read_only=True)
    user_id    = serializers.IntegerField(source='user.id',    read_only=True)
    total_points = serializers.SerializerMethodField()
    badges = serializers.SerializerMethodField()
    followers_count = serializers.SerializerMethodField()
    following_count = serializers.SerializerMethodField()
    avatar = AbsoluteImageField(required=False, allow_null=True)

    class Meta:
        model  = UserProfile
        fields = [
            'user_id', 'username', 'email', 'display_name', 'first_name',
            'last_name', 'gender', 'bio', 'profile_message', 'avatar',
            'orcid', 'linkedin_url', 'google_scholar_url',
            'other_platform_url', 'publications', 'badges_ready',
            'total_points', 'badges', 'created_at',
            'followers_count', 'following_count',
        ]

    def get_total_points(self, obj):
        from .gamification import platform_points_for_user
        return platform_points_for_user(obj.user)['points']

    def get_badges(self, obj):
        explicit = UserBadge.objects.filter(user=obj.user, evaluation__isnull=True)
        data = UserBadgeSerializer(explicit, many=True).data
        if obj.badges_ready:
            from .gamification import inferred_platform_badges
            data.extend(inferred_platform_badges(obj.user))
        return data

    def get_followers_count(self, obj):
        return obj.user.follower_links.count()

    def get_following_count(self, obj):
        return obj.user.following_links.count()


class PublicUserProfileSerializer(serializers.ModelSerializer):
    user_id = serializers.IntegerField(source='user.id', read_only=True)
    username = serializers.CharField(source='user.username', read_only=True)
    display_name = serializers.CharField(read_only=True)
    total_points = serializers.SerializerMethodField()
    badges = serializers.SerializerMethodField()
    followers_count = serializers.SerializerMethodField()
    following_count = serializers.SerializerMethodField()
    is_following = serializers.SerializerMethodField()
    avatar = AbsoluteImageField(read_only=True)
    public_evaluations = serializers.SerializerMethodField()

    class Meta:
        model = UserProfile
        fields = [
            'user_id', 'username', 'display_name', 'first_name', 'last_name',
            'gender', 'bio', 'profile_message', 'avatar', 'orcid',
            'linkedin_url', 'google_scholar_url', 'other_platform_url',
            'publications', 'total_points', 'badges',
            'followers_count', 'following_count', 'is_following',
            'public_evaluations',
        ]

    def get_total_points(self, obj):
        from .gamification import platform_points_for_user
        return platform_points_for_user(obj.user)['points']

    def get_badges(self, obj):
        if not obj.badges_ready:
            return []
        from .gamification import inferred_platform_badges
        return inferred_platform_badges(obj.user)

    def get_followers_count(self, obj):
        return obj.user.follower_links.count()

    def get_following_count(self, obj):
        return obj.user.following_links.count()

    def get_is_following(self, obj):
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return False
        return UserFollow.objects.filter(follower=request.user, following=obj.user).exists()

    def get_public_evaluations(self, obj):
        from .gamification import evaluation_points_for_user
        user = obj.user
        qs = (
            Evaluation.objects.filter(is_public=True)
            .filter(
                models.Q(owner=user)
                | models.Q(judges=user)
                | models.Q(reviewers=user)
                | models.Q(viewers=user)
            )
            .distinct()
            .select_related('owner', 'dataset')
            .prefetch_related('judges', 'reviewers', 'viewers')
            .order_by('-updated_at')[:20]
        )
        data = []
        for ev in qs:
            roles = []
            if ev.owner_id == user.pk:
                roles.append('owner')
            if ev.judges.filter(pk=user.pk).exists():
                roles.append('judge')
            if ev.reviewers.filter(pk=user.pk).exists():
                roles.append('reviewer')
            if ev.viewers.filter(pk=user.pk).exists():
                roles.append('viewer')
            data.append({
                'id': ev.id,
                'name': ev.name,
                'status': ev.status,
                'roles': roles,
                'points': evaluation_points_for_user(ev, user)['points'],
            })
        return data


class UserBadgeSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserBadge
        fields = ['id', 'code', 'title', 'description', 'points', 'evaluation', 'awarded_at']


class FriendInvitationSerializer(serializers.ModelSerializer):
    sender = UserMiniSerializer(read_only=True)
    receiver = UserMiniSerializer(read_only=True)

    class Meta:
        model = FriendInvitation
        fields = [
            'id', 'sender', 'receiver', 'suggested_role', 'message',
            'status', 'created_at', 'updated_at',
        ]


class UserFollowSerializer(serializers.ModelSerializer):
    follower = UserMiniSerializer(read_only=True)
    following = UserMiniSerializer(read_only=True)

    class Meta:
        model = UserFollow
        fields = ['id', 'follower', 'following', 'created_at']


class EvaluationMessageSerializer(serializers.ModelSerializer):
    author = UserMiniSerializer(read_only=True)

    class Meta:
        model = EvaluationMessage
        fields = ['id', 'evaluation', 'author', 'body', 'created_at']


class NotificationSerializer(serializers.ModelSerializer):
    actor = UserMiniSerializer(read_only=True)

    class Meta:
        model = Notification
        fields = [
            'id', 'kind', 'title', 'body', 'actor', 'evaluation',
            'data', 'read_at', 'created_at',
        ]


# ---------------------------------------------------------------------------
# Dataset
# ---------------------------------------------------------------------------
class DatasetColumnSerializer(serializers.ModelSerializer):
    class Meta:
        model  = DatasetColumn
        fields = '__all__'


class DatasetSerializer(serializers.ModelSerializer):
    columns = DatasetColumnSerializer(many=True, read_only=True)

    class Meta:
        model  = Dataset
        fields = ['id', 'name', 'created_by', 'created_at', 'delimiter',
                  'encoding', 'version', 'original_file', 'columns']


class DatasetItemSerializer(serializers.ModelSerializer):
    class Meta:
        model  = DatasetItem
        fields = ['id', 'row_index', 'data']


# ---------------------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------------------
class EvaluationSerializer(serializers.ModelSerializer):
    owner     = UserMiniSerializer(read_only=True)
    judges    = serializers.PrimaryKeyRelatedField(many=True, queryset=User.objects.all(), required=False)
    reviewers = serializers.PrimaryKeyRelatedField(many=True, queryset=User.objects.all(), required=False)
    viewers   = serializers.PrimaryKeyRelatedField(many=True, queryset=User.objects.all(), required=False)
    judges_detail = UserMiniSerializer(source='judges', many=True, read_only=True)
    reviewers_detail = UserMiniSerializer(source='reviewers', many=True, read_only=True)
    viewers_detail = UserMiniSerializer(source='viewers', many=True, read_only=True)

    class Meta:
        model  = Evaluation
        fields = '__all__'

    def create(self, validated_data):
        judges    = validated_data.pop('judges',    [])
        reviewers = validated_data.pop('reviewers', [])
        viewers   = validated_data.pop('viewers',   [])
        req       = self.context['request']
        ev = Evaluation.objects.create(owner=req.user, status='open', **validated_data)
        # Owner is always a judge
        ev.judges.set(list({*judges, req.user}))
        ev.reviewers.set(reviewers)
        ev.viewers.set(viewers)
        return ev

    def update(self, instance, validated_data):
        judges    = validated_data.pop('judges',    None)
        reviewers = validated_data.pop('reviewers', None)
        viewers   = validated_data.pop('viewers',   None)
        for attr, value in validated_data.items():
            setattr(instance, attr, value)
        instance.save()
        if judges    is not None: instance.judges.set(judges)
        if reviewers is not None: instance.reviewers.set(reviewers)
        if viewers   is not None: instance.viewers.set(viewers)
        return instance


class PublicEvaluationSerializer(serializers.ModelSerializer):
    owner = UserMiniSerializer(read_only=True)
    dataset_name = serializers.CharField(source='dataset.name', read_only=True)
    member_counts = serializers.SerializerMethodField()
    my_roles = serializers.SerializerMethodField()

    class Meta:
        model = Evaluation
        fields = [
            'id', 'name', 'status', 'owner', 'dataset', 'dataset_name',
            'created_at', 'updated_at', 'is_public', 'public_join_roles',
            'labeling_instructions', 'allow_multiple_labels',
            'member_counts', 'my_roles',
        ]

    def get_member_counts(self, obj):
        return {
            'judges': obj.judges.count(),
            'reviewers': obj.reviewers.count(),
            'viewers': obj.viewers.count(),
        }

    def get_my_roles(self, obj):
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return []
        user = request.user
        roles = []
        if obj.owner_id == user.pk:
            roles.append('owner')
        if obj.judges.filter(pk=user.pk).exists():
            roles.append('judge')
        if obj.reviewers.filter(pk=user.pk).exists():
            roles.append('reviewer')
        if obj.viewers.filter(pk=user.pk).exists():
            roles.append('viewer')
        return roles


# ---------------------------------------------------------------------------
# Judgment & Review
# ---------------------------------------------------------------------------
class JudgmentSerializer(serializers.ModelSerializer):
    judge_username = serializers.CharField(source='judge.username', read_only=True)
    labels = serializers.SerializerMethodField()

    class Meta:
        model  = Judgment
        fields = ['id', 'judge', 'judge_username', 'value', 'labels', 'confidence', 'created_at']

    def get_labels(self, obj):
        labels = obj.labels or []
        if labels:
            return labels
        return [obj.value] if obj.value else []


class ReviewSerializer(serializers.ModelSerializer):
    reviewer_username = serializers.CharField(source='reviewer.username', read_only=True)

    class Meta:
        model  = Review
        fields = ['id', 'reviewer', 'reviewer_username', 'notes', 'accepted_value', 'created_at']


class LLMRunSerializer(serializers.ModelSerializer):
    class Meta:
        model = LLMRun
        fields = [
            'id', 'feature', 'provider', 'model_name', 'prompt_version',
            'input_hash', 'duration_ms', 'status', 'error', 'created_at',
        ]


class LabelNormalizationProposalSerializer(serializers.ModelSerializer):
    llm_run = LLMRunSerializer(read_only=True)

    class Meta:
        model = LabelNormalizationProposal
        fields = [
            'id', 'dataset', 'llm_run', 'label_column', 'distinct_labels',
            'proposed_mapping', 'approved_mapping', 'status', 'created_at',
            'decided_at',
        ]


class RoutingSuggestionSerializer(serializers.ModelSerializer):
    llm_run = LLMRunSerializer(read_only=True)

    class Meta:
        model = RoutingSuggestion
        fields = [
            'id', 'evaluation', 'llm_run', 'item_scores', 'summary',
            'status', 'created_at', 'decided_at',
        ]


class CodebookSerializer(serializers.ModelSerializer):
    llm_run = LLMRunSerializer(read_only=True)

    class Meta:
        model = Codebook
        fields = [
            'id', 'evaluation', 'llm_run', 'content', 'markdown',
            'status', 'version', 'created_at', 'published_at',
        ]


class DisagreementDiagnosisSerializer(serializers.ModelSerializer):
    llm_run = LLMRunSerializer(read_only=True)

    class Meta:
        model = DisagreementDiagnosis
        fields = [
            'id', 'evaluation', 'item', 'llm_run', 'cause', 'explanation',
            'payload', 'created_at',
        ]


class ConsistencyFindingSerializer(serializers.ModelSerializer):
    llm_run = LLMRunSerializer(read_only=True)

    class Meta:
        model = ConsistencyFinding
        fields = [
            'id', 'evaluation', 'judge', 'llm_run', 'item_a', 'item_b',
            'label_a', 'label_b', 'justification', 'status', 'feedback',
            'created_at', 'resolved_at',
        ]


class ThreatsValidityReportSerializer(serializers.ModelSerializer):
    llm_run = LLMRunSerializer(read_only=True)

    class Meta:
        model = ThreatsValidityReport
        fields = [
            'id', 'evaluation', 'llm_run', 'stats_snapshot', 'report',
            'markdown', 'created_at',
        ]

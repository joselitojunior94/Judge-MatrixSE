from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone
from django.core.validators import MinValueValidator
from django.db.models.signals import post_save
from django.dispatch import receiver


# ---------------------------------------------------------------------------
# Phase 0 — User profile (extends Django's built-in User)
# ---------------------------------------------------------------------------
class UserProfile(models.Model):
    GENDER_CHOICES = [
        ('', 'Prefer not to say'),
        ('female', 'Female'),
        ('male', 'Male'),
        ('non_binary', 'Non-binary'),
        ('other', 'Other'),
    ]

    user         = models.OneToOneField(User, on_delete=models.CASCADE, related_name='profile')
    display_name = models.CharField(max_length=150, blank=True)
    first_name   = models.CharField(max_length=150, blank=True)
    last_name    = models.CharField(max_length=150, blank=True)
    gender       = models.CharField(max_length=32, choices=GENDER_CHOICES, blank=True, default='')
    bio          = models.TextField(blank=True)
    profile_message = models.CharField(max_length=280, blank=True)
    avatar       = models.ImageField(upload_to='avatars/', null=True, blank=True)
    orcid        = models.CharField(max_length=32, blank=True)
    linkedin_url = models.URLField(blank=True)
    google_scholar_url = models.URLField(blank=True)
    other_platform_url = models.URLField(blank=True)
    publications = models.JSONField(default=list, blank=True)
    badges_ready = models.BooleanField(default=True)
    created_at   = models.DateTimeField(default=timezone.now)

    def __str__(self):
        return f'Profile({self.user.username})'

@receiver(post_save, sender=User)
def _create_profile(sender, instance, created, **kwargs):
    """Auto-create a UserProfile whenever a new User is saved."""
    if created:
        UserProfile.objects.get_or_create(user=instance)


class Dataset(models.Model):
    name = models.CharField(max_length=200)
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='datasets')
    created_at = models.DateTimeField(default=timezone.now)
    original_file = models.FileField(upload_to='datasets/')
    delimiter = models.CharField(max_length=4, default=',')
    encoding = models.CharField(max_length=32, default='UTF-8')
    version = models.IntegerField(default=1)

class DatasetColumn(models.Model):
    ROLE_CHOICES = [('ID','ID'),('TEXT','TEXT'),('FEATURE','FEATURE'),('LABEL','LABEL'),('IGNORE','IGNORE')]

    dataset = models.ForeignKey(Dataset, on_delete=models.CASCADE, related_name='columns')
    name_in_file = models.CharField(max_length=200)
    mapped_name = models.CharField(max_length=200)
    role = models.CharField(max_length=10, choices=ROLE_CHOICES, default='FEATURE')
    dtype = models.CharField(max_length=20, default='string')
    required = models.BooleanField(default=False)

class DatasetItem(models.Model):
    dataset = models.ForeignKey(Dataset, on_delete=models.CASCADE, related_name='items')
    row_index = models.IntegerField(validators=[MinValueValidator(0)])
    data = models.JSONField()

    class Meta: unique_together = ('dataset','row_index')

class Evaluation(models.Model):
    name = models.CharField(max_length=200)
    dataset = models.ForeignKey(Dataset, on_delete=models.CASCADE, related_name='evaluations')
    owner = models.ForeignKey(User, on_delete=models.CASCADE, related_name='owned_evaluations')
    judges = models.ManyToManyField(User, related_name='judge_evaluations', blank=True)
    reviewers = models.ManyToManyField(User, related_name='review_evaluations', blank=True)
    viewers = models.ManyToManyField(User, related_name='view_evaluations', blank=True)
    status = models.CharField(max_length=20, default='draft') 
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)
    metrics = models.JSONField(default=dict, blank=True)
    is_public = models.BooleanField(default=False)
    public_join_roles = models.JSONField(default=list, blank=True)
    labeling_instructions = models.TextField(blank=True)
    allow_multiple_labels = models.BooleanField(default=False)


class Notification(models.Model):
    KIND_CHOICES = [
        ('profile', 'Profile'),
        ('evaluation_invite', 'Evaluation invite'),
        ('evaluation', 'Evaluation'),
        ('follow', 'Follow'),
        ('chat', 'Chat'),
        ('points', 'Points'),
        ('activity', 'Activity'),
    ]

    recipient = models.ForeignKey(User, on_delete=models.CASCADE, related_name='notifications')
    actor = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='triggered_notifications')
    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, null=True, blank=True, related_name='notifications')
    kind = models.CharField(max_length=40, choices=KIND_CHOICES)
    title = models.CharField(max_length=160)
    body = models.TextField(blank=True)
    data = models.JSONField(default=dict, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ['-created_at']

class Judgment(models.Model):
    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='judgments')
    item = models.ForeignKey(DatasetItem, on_delete=models.CASCADE, related_name='judgments')
    judge = models.ForeignKey(User, on_delete=models.CASCADE, related_name='judgments')
    value = models.CharField(max_length=200)
    labels = models.JSONField(default=list, blank=True)
    confidence = models.FloatField(null=True, blank=True)
    created_at = models.DateTimeField(default=timezone.now)
    class Meta: unique_together = ('evaluation','item','judge')

class Review(models.Model):
    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='reviews')
    item = models.ForeignKey(DatasetItem, on_delete=models.CASCADE, related_name='reviews')
    reviewer = models.ForeignKey(User, on_delete=models.CASCADE, related_name='reviews')
    notes = models.TextField(blank=True)
    accepted_value = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(default=timezone.now)
    class Meta: unique_together = ('evaluation','item','reviewer')


class FriendInvitation(models.Model):
    ROLE_CHOICES = [
        ('judge', 'Judge'),
        ('reviewer', 'Reviewer'),
        ('viewer', 'Viewer'),
        ('evaluator', 'Evaluator'),
        ('friend', 'Friend'),
    ]
    STATUS_CHOICES = [
        ('pending', 'Pending'),
        ('accepted', 'Accepted'),
        ('declined', 'Declined'),
    ]

    sender = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sent_friend_invitations')
    receiver = models.ForeignKey(User, on_delete=models.CASCADE, related_name='received_friend_invitations')
    suggested_role = models.CharField(max_length=20, choices=ROLE_CHOICES, default='friend')
    message = models.CharField(max_length=280, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='pending')
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        unique_together = ('sender', 'receiver', 'suggested_role')


class UserFollow(models.Model):
    follower = models.ForeignKey(User, on_delete=models.CASCADE, related_name='following_links')
    following = models.ForeignKey(User, on_delete=models.CASCADE, related_name='follower_links')
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        unique_together = ('follower', 'following')
        ordering = ['-created_at']


class UserBadge(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='badges')
    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='badges', null=True, blank=True)
    code = models.CharField(max_length=80)
    title = models.CharField(max_length=120)
    description = models.TextField(blank=True)
    points = models.PositiveIntegerField(default=0)
    awarded_at = models.DateTimeField(default=timezone.now)

    class Meta:
        unique_together = ('user', 'evaluation', 'code')


class EvaluationMessage(models.Model):
    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='messages')
    author = models.ForeignKey(User, on_delete=models.CASCADE, related_name='evaluation_messages')
    body = models.TextField()
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ['created_at']


class LLMRun(models.Model):
    FEATURE_CHOICES = [
        ('label_normalization', 'Semantic label normalization'),
        ('effort_routing', 'Effort estimation and queue routing'),
        ('codebook_induction', 'Codebook induction'),
        ('disagreement_diagnosis', 'Disagreement diagnosis'),
        ('consistency_audit', 'Intra-judge consistency audit'),
        ('threats_validity', 'Threats-to-validity report'),
    ]

    feature = models.CharField(max_length=40, choices=FEATURE_CHOICES)
    provider = models.CharField(max_length=40)
    model_name = models.CharField(max_length=120)
    prompt_version = models.CharField(max_length=80)
    input_hash = models.CharField(max_length=64)
    prompt = models.TextField(blank=True)
    output_text = models.TextField(blank=True)
    output_json = models.JSONField(default=dict, blank=True)
    raw_response = models.JSONField(default=dict, blank=True)
    duration_ms = models.PositiveIntegerField(default=0)
    status = models.CharField(max_length=20, default='completed')
    error = models.TextField(blank=True)
    created_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='llm_runs')
    dataset = models.ForeignKey(Dataset, on_delete=models.CASCADE, null=True, blank=True, related_name='llm_runs')
    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, null=True, blank=True, related_name='llm_runs')
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ['-created_at']


class LabelNormalizationProposal(models.Model):
    STATUS_CHOICES = [
        ('draft', 'Draft'),
        ('approved', 'Approved'),
        ('rejected', 'Rejected'),
    ]

    dataset = models.ForeignKey(Dataset, on_delete=models.CASCADE, related_name='label_normalization_proposals')
    llm_run = models.ForeignKey(LLMRun, on_delete=models.SET_NULL, null=True, blank=True, related_name='label_normalization_proposals')
    label_column = models.CharField(max_length=200)
    distinct_labels = models.JSONField(default=list, blank=True)
    proposed_mapping = models.JSONField(default=dict, blank=True)
    approved_mapping = models.JSONField(default=dict, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='label_normalization_proposals')
    decided_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='decided_label_normalizations')
    created_at = models.DateTimeField(default=timezone.now)
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']


class RoutingSuggestion(models.Model):
    STATUS_CHOICES = [
        ('draft', 'Draft'),
        ('accepted', 'Accepted'),
        ('ignored', 'Ignored'),
    ]

    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='routing_suggestions')
    llm_run = models.ForeignKey(LLMRun, on_delete=models.SET_NULL, null=True, blank=True, related_name='routing_suggestions')
    item_scores = models.JSONField(default=list, blank=True)
    summary = models.JSONField(default=dict, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='routing_suggestions')
    decided_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='decided_routing_suggestions')
    created_at = models.DateTimeField(default=timezone.now)
    decided_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']


class Codebook(models.Model):
    STATUS_CHOICES = [
        ('draft', 'Draft'),
        ('published', 'Published'),
        ('archived', 'Archived'),
    ]

    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='codebooks')
    llm_run = models.ForeignKey(LLMRun, on_delete=models.SET_NULL, null=True, blank=True, related_name='codebooks')
    content = models.JSONField(default=dict, blank=True)
    markdown = models.TextField(blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='draft')
    version = models.PositiveIntegerField(default=1)
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='created_codebooks')
    published_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='published_codebooks')
    created_at = models.DateTimeField(default=timezone.now)
    published_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-version', '-created_at']


class DisagreementDiagnosis(models.Model):
    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='disagreement_diagnoses')
    item = models.ForeignKey(DatasetItem, on_delete=models.CASCADE, related_name='disagreement_diagnoses')
    llm_run = models.ForeignKey(LLMRun, on_delete=models.SET_NULL, null=True, blank=True, related_name='disagreement_diagnoses')
    cause = models.CharField(max_length=80, blank=True)
    explanation = models.TextField(blank=True)
    payload = models.JSONField(default=dict, blank=True)
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='disagreement_diagnoses')
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ['-created_at']


class ConsistencyFinding(models.Model):
    STATUS_CHOICES = [
        ('open', 'Open'),
        ('corrected', 'Corrected'),
        ('genuinely_different', 'Genuinely different'),
        ('dismissed', 'Dismissed'),
    ]

    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='consistency_findings')
    judge = models.ForeignKey(User, on_delete=models.CASCADE, related_name='consistency_findings')
    llm_run = models.ForeignKey(LLMRun, on_delete=models.SET_NULL, null=True, blank=True, related_name='consistency_findings')
    item_a = models.ForeignKey(DatasetItem, on_delete=models.CASCADE, related_name='consistency_findings_as_a')
    item_b = models.ForeignKey(DatasetItem, on_delete=models.CASCADE, related_name='consistency_findings_as_b')
    label_a = models.CharField(max_length=200)
    label_b = models.CharField(max_length=200)
    justification = models.TextField(blank=True)
    status = models.CharField(max_length=30, choices=STATUS_CHOICES, default='open')
    feedback = models.TextField(blank=True)
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='created_consistency_findings')
    resolved_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True, related_name='resolved_consistency_findings')
    created_at = models.DateTimeField(default=timezone.now)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']


class ThreatsValidityReport(models.Model):
    evaluation = models.ForeignKey(Evaluation, on_delete=models.CASCADE, related_name='threat_reports')
    llm_run = models.ForeignKey(LLMRun, on_delete=models.SET_NULL, null=True, blank=True, related_name='threat_reports')
    stats_snapshot = models.JSONField(default=dict, blank=True)
    report = models.JSONField(default=dict, blank=True)
    markdown = models.TextField(blank=True)
    created_by = models.ForeignKey(User, on_delete=models.CASCADE, related_name='threat_reports')
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ['-created_at']

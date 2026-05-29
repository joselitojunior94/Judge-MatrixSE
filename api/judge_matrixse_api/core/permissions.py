"""
Per-evaluation role-based permission classes.

Roles (scoped per evaluation):
  Owner    — created the evaluation; full control + is also a judge
  Judge    — may read items and submit/update their own judgments
  Reviewer — may read items + judgments and submit reviews
  Viewer   — read-only access to results/metrics

Helper
-------
get_eval_role(user, evaluation) → 'owner' | 'judge' | 'reviewer' | 'viewer' | None
"""
from rest_framework.permissions import BasePermission


def get_eval_role(user, evaluation):
    """Return the highest role this user holds in the evaluation, or None."""
    if not user or not user.is_authenticated:
        return None
    if evaluation.owner_id == user.pk:
        return 'owner'
    if evaluation.judges.filter(pk=user.pk).exists():
        return 'judge'
    if evaluation.reviewers.filter(pk=user.pk).exists():
        return 'reviewer'
    if evaluation.viewers.filter(pk=user.pk).exists():
        return 'viewer'
    return None


class IsEvaluationMember(BasePermission):
    """Allow any member of the evaluation (owner/judge/reviewer/viewer)."""
    message = 'You are not a member of this evaluation.'

    def has_object_permission(self, request, view, obj):
        # obj is an Evaluation instance
        return get_eval_role(request.user, obj) is not None


class IsEvaluationOwner(BasePermission):
    """Allow only the evaluation owner."""
    message = 'Only the evaluation owner can perform this action.'

    def has_object_permission(self, request, view, obj):
        return obj.owner_id == request.user.pk


class IsJudgeOrOwner(BasePermission):
    """Allow judges and owners (both can submit judgments)."""
    message = 'Only judges and the owner can submit judgments.'

    def has_object_permission(self, request, view, obj):
        role = get_eval_role(request.user, obj)
        return role in ('owner', 'judge')


class IsReviewerOrOwner(BasePermission):
    """Allow reviewers and owners (both can submit reviews)."""
    message = 'Only reviewers and the owner can submit reviews.'

    def has_object_permission(self, request, view, obj):
        role = get_eval_role(request.user, obj)
        return role in ('owner', 'reviewer')

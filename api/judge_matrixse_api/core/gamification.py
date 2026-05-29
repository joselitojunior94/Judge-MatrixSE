from django.contrib.auth.models import User
from django.conf import settings
from django.db.models import Count, Q

from .models import Evaluation, Judgment, Review, UserBadge


POINTS = {
    'dataset': 5,
    'owned_evaluation': 15,
    'judgment': 10,
    'review': 8,
    'badge': 20,
}


def platform_points_for_user(user):
    datasets = user.datasets.count()
    owned_evaluations = user.owned_evaluations.count()
    judgments = user.judgments.count()
    reviews = user.reviews.count()
    explicit_badges = user.badges.filter(evaluation__isnull=True).count()
    points = (
        datasets * POINTS['dataset']
        + owned_evaluations * POINTS['owned_evaluation']
        + judgments * POINTS['judgment']
        + reviews * POINTS['review']
        + explicit_badges * POINTS['badge']
    )
    return {
        'points': points,
        'datasets': datasets,
        'owned_evaluations': owned_evaluations,
        'judgments': judgments,
        'reviews': reviews,
        'badges': explicit_badges,
    }


def inferred_platform_badges(user):
    stats = platform_points_for_user(user)
    badges = []
    if stats['judgments'] >= 1:
        badges.append({
            'code': 'first_judgment',
            'title': 'First Judgment',
            'description': 'Submitted the first human judgment.',
            'points': 10,
            'evaluation': None,
        })
    if stats['reviews'] >= 1:
        badges.append({
            'code': 'first_review',
            'title': 'First Review',
            'description': 'Submitted the first review.',
            'points': 10,
            'evaluation': None,
        })
    if stats['judgments'] >= 25:
        badges.append({
            'code': 'active_judge',
            'title': 'Active Judge',
            'description': 'Submitted at least 25 judgments.',
            'points': 30,
            'evaluation': None,
        })
    return badges


def platform_ranking(limit=50):
    rows = []
    qs = User.objects.select_related('profile').all()
    for user in qs:
        stats = platform_points_for_user(user)
        rows.append(_rank_row(user, stats))
    rows.sort(key=lambda r: (-r['points'], r['username']))
    return rows[:limit]


def evaluation_ranking(evaluation):
    members = User.objects.filter(
        Q(pk=evaluation.owner_id)
        | Q(judge_evaluations=evaluation)
        | Q(review_evaluations=evaluation)
        | Q(view_evaluations=evaluation)
    ).distinct().select_related('profile')

    judgment_counts = dict(
        Judgment.objects.filter(evaluation=evaluation)
        .values('judge_id')
        .annotate(count=Count('id'))
        .values_list('judge_id', 'count')
    )
    review_counts = dict(
        Review.objects.filter(evaluation=evaluation)
        .values('reviewer_id')
        .annotate(count=Count('id'))
        .values_list('reviewer_id', 'count')
    )
    badge_counts = dict(
        UserBadge.objects.filter(evaluation=evaluation)
        .values('user_id')
        .annotate(count=Count('id'))
        .values_list('user_id', 'count')
    )

    rows = []
    for user in members:
        judgments = judgment_counts.get(user.pk, 0)
        reviews = review_counts.get(user.pk, 0)
        badges = badge_counts.get(user.pk, 0)
        owner_bonus = 1 if evaluation.owner_id == user.pk else 0
        points = (
            judgments * POINTS['judgment']
            + reviews * POINTS['review']
            + badges * POINTS['badge']
            + owner_bonus * POINTS['owned_evaluation']
        )
        rows.append(_rank_row(user, {
            'points': points,
            'judgments': judgments,
            'reviews': reviews,
            'badges': badges,
            'owner_bonus': owner_bonus,
        }))

    judges = [r for r in rows if r['stats']['judgments'] > 0 or evaluation.judges.filter(pk=r['user_id']).exists()]
    evaluators = [r for r in rows if r['stats']['reviews'] > 0 or evaluation.reviewers.filter(pk=r['user_id']).exists()]

    key = lambda r: (-r['points'], r['username'])
    return {
        'evaluation': evaluation.id,
        'name': evaluation.name,
        'judges': sorted(judges, key=key),
        'evaluators': sorted(evaluators, key=key),
        'total': sorted(rows, key=key),
        'points_policy': POINTS,
    }


def evaluation_points_for_user(evaluation, user):
    judgments = Judgment.objects.filter(evaluation=evaluation, judge=user).count()
    reviews = Review.objects.filter(evaluation=evaluation, reviewer=user).count()
    badges = UserBadge.objects.filter(evaluation=evaluation, user=user).count()
    owner_bonus = 1 if evaluation.owner_id == user.pk else 0
    points = (
        judgments * POINTS['judgment']
        + reviews * POINTS['review']
        + badges * POINTS['badge']
        + owner_bonus * POINTS['owned_evaluation']
    )
    return {
        'points': points,
        'judgments': judgments,
        'reviews': reviews,
        'badges': badges,
        'owner_bonus': owner_bonus,
    }


def _rank_row(user, stats):
    profile = getattr(user, 'profile', None)
    display_name = getattr(profile, 'display_name', '') or user.username
    avatar = getattr(profile, 'avatar', None)
    return {
        'user_id': user.pk,
        'username': user.username,
        'display_name': display_name,
        'avatar': _avatar_url(avatar),
        'points': stats['points'],
        'stats': stats,
    }


def _avatar_url(avatar):
    if not avatar:
        return None
    try:
        url = avatar.url
    except ValueError:
        return None
    if settings.PUBLIC_API_BASE_URL:
        return f"{settings.PUBLIC_API_BASE_URL}{url}"
    return url

from django.urls import path, include
from rest_framework.routers import DefaultRouter
from . import views

router = DefaultRouter()
router.register(r'datasets',    views.DatasetViewSet,    basename='dataset')
router.register(r'evaluations', views.EvaluationViewSet, basename='evaluation')

urlpatterns = [
    path('health/', views.health),

    # ---- Auth & profile ------------------------------------------------
    path('auth/register/',   views.register),
    path('auth/me/',         views.me),
    path('auth/me/update/',  views.update_me),
    path('auth/me/publications/sync/', views.sync_publications),
    path('notifications/', views.notifications),
    path('notifications/read/', views.mark_notifications_read),

    # ---- User search (collaborator lookup) -----------------------------
    path('users/',           views.user_search),
    path('users/<int:user_id>/profile/', views.public_user_profile),
    path('users/<int:user_id>/follows/', views.user_follow_lists),
    path('friends/',         views.friends),
    path('friends/invite/',  views.invite_friend),
    path('friends/<int:user_id>/unfollow/', views.unfollow_user),
    path('friends/<int:invitation_id>/respond/', views.respond_friend_invite),
    path('rankings/platform/', views.platform_rankings),
    path('evaluations/public/', views.public_evaluations),
    path('evaluations/<int:eval_id>/join/', views.join_public_evaluation),

    # ---- Dataset upload & mapping -------------------------------------
    path('datasets/upload-csv/',                             views.UploadCsvView.as_view()),
    path('datasets/<int:dataset_id>/upload-csv/',            views.UploadCsvView.as_view()),
    path('datasets/<int:dataset_id>/versions/<int:version>/mapping/', views.save_mapping),
    path('datasets/<int:dataset_id>/llm/label-normalization/', views.generate_label_normalization),
    path('llm/label-normalization/<int:proposal_id>/', views.decide_label_normalization),

    # ---- Evaluation items, judgments, reviews -------------------------
    path('evaluations/<int:eval_id>/items/',                            views.EvaluationItemsView.as_view()),
    path('evaluations/<int:eval_id>/items/<int:item_id>/judgments/',   views.JudgmentView.as_view()),
    path('evaluations/<int:eval_id>/items/<int:item_id>/reviews/',     views.ReviewView.as_view()),
    path('evaluations/<int:eval_id>/items/<int:item_id>/llm/disagreement/', views.item_disagreement_diagnosis),
    path('evaluations/<int:eval_id>/chat/', views.evaluation_chat),

    # ---- Metrics & results --------------------------------------------
    path('evaluations/<int:eval_id>/metrics/', views.evaluation_metrics),
    path('evaluations/<int:eval_id>/results/', views.evaluation_results),
    path('evaluations/<int:eval_id>/rankings/', views.evaluation_rankings),
    path('evaluations/<int:eval_id>/threat-report/', views.threat_report),
    path('evaluations/<int:eval_id>/llm/routing/', views.effort_routing),
    path('llm/routing/<int:suggestion_id>/', views.decide_effort_routing),
    path('evaluations/<int:eval_id>/codebooks/', views.codebooks),
    path('codebooks/<int:codebook_id>/', views.codebook_detail),
    path('evaluations/<int:eval_id>/llm/consistency/', views.consistency_audit),
    path('llm/consistency/<int:finding_id>/', views.consistency_finding_detail),

    # ---- Export -------------------------------------------------------
    path('evaluations/<int:eval_id>/export/csv/',  views.export_results_csv),
    path('evaluations/<int:eval_id>/export/json/', views.export_results_json),

    # ---- Lifecycle ----------------------------------------------------
    path('evaluations/<int:eval_id>/open/',   views.open_evaluation),
    path('evaluations/<int:eval_id>/close/',  views.close_evaluation),
    path('evaluations/<int:eval_id>/freeze/', views.freeze_evaluation),

    # ---- Legacy (410 Gone) -------------------------------------------
    path('gemini/suggest/', views.ai_suggest),

    # ---- Phase 8 — LLM meta-evaluation (read-only, member-gated) ------
    path('evaluations/<int:eval_id>/meta/disagreement/', views.meta_disagreement),
    path('evaluations/<int:eval_id>/meta/effort/',       views.meta_effort),
    path('evaluations/<int:eval_id>/meta/consistency/',  views.meta_consistency),
    path('evaluations/<int:eval_id>/meta/codebook/',     views.meta_codebook),
    path('evaluations/<int:eval_id>/meta/validity/',     views.meta_validity),
    path('evaluations/<int:eval_id>/meta/normalise/',    views.meta_normalise),

    path('', include(router.urls)),
]

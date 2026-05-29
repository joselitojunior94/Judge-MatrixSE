"""
Phase 8 — Six meta-evaluation features.

Non-negotiable safety rules (enforced by design):
  1. No function here writes to Judgment or Review tables.
  2. All outputs are marked with llm_provider / llm_model / prompt_version.
  3. Functions only receive aggregated statistics or anonymised text —
     never raw item rows that a human judge hasn't seen yet.
  4. All callers must store results in a separate, clearly labelled
     field (e.g. EvaluationMetaReport) — never mixed with human labels.
"""
from __future__ import annotations

import json
from collections import Counter, defaultdict
from itertools import combinations
from typing import Any

from .llm_service import call as llm_call, LLMResult


# ─────────────────────────────────────────────────────────────────────────────
# 1. Disagreement diagnosis
#    Input:  list of {item_id, judge_id, label} dicts (no item text)
#    Output: LLM analysis of disagreement patterns + suggested root causes
# ─────────────────────────────────────────────────────────────────────────────
def disagreement_diagnosis(judgments: list[dict]) -> dict[str, Any]:
    """
    Identify items with high disagreement and return LLM-generated explanations.
    """
    # Group by item
    by_item: dict[int, list[str]] = defaultdict(list)
    for j in judgments:
        by_item[j['item_id']].append(str(j['label']))

    disputed = [
        {
            'item_id': iid,
            'labels': labels,
            'n_unique': len(set(labels)),
        }
        for iid, labels in by_item.items()
        if len(set(labels)) > 1
    ]
    disputed.sort(key=lambda x: x['n_unique'], reverse=True)
    top_disputed = disputed[:20]

    if not top_disputed:
        return {
            'disputed_items': 0,
            'analysis': 'No disagreement found — all judges agree on every item.',
            'llm_meta': None,
        }

    prompt = (
        "You are analysing inter-rater disagreements in a labeling study. "
        "IMPORTANT: do NOT suggest which label is correct — you are NOT a judge. "
        "Only describe the pattern of disagreement and potential root causes.\n\n"
        f"Top disputed items (item_id → labels assigned by different judges):\n"
        f"{json.dumps(top_disputed, indent=2)}\n\n"
        "Return JSON with keys:\n"
        "  patterns: [list of disagreement patterns observed]\n"
        "  root_causes: [list of plausible root causes]\n"
        "  codebook_gaps: [areas where the codebook may be ambiguous]\n"
        "  recommendation: string"
    )

    result: LLMResult = llm_call(prompt, prompt_version="disagreement-diagnosis-v1")
    return {
        'disputed_items': len(disputed),
        'top_disputed':   top_disputed,
        'analysis':       result.text,
        'llm_meta':       result.to_dict(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 2. Effort estimation
#    Input:  list of {judge_id, item_id, created_at} dicts
#    Output: per-judge mean time-per-item, anomalies, fatigue signals
# ─────────────────────────────────────────────────────────────────────────────
def effort_estimation(judgments: list[dict]) -> dict[str, Any]:
    """
    Estimate labeling effort from submission timestamps.
    """
    from datetime import datetime

    # Sort per judge by created_at, compute gaps
    by_judge: dict[Any, list[datetime]] = defaultdict(list)
    for j in judgments:
        ts = j.get('created_at')
        if ts:
            if isinstance(ts, str):
                ts = datetime.fromisoformat(ts.replace('Z', '+00:00'))
            by_judge[j['judge_id']].append(ts)

    stats: list[dict] = []
    for jid, times in by_judge.items():
        times.sort()
        gaps = [
            (times[i + 1] - times[i]).total_seconds()
            for i in range(len(times) - 1)
        ]
        plausible = [g for g in gaps if 1 < g < 600]  # 1s–10min heuristic
        stats.append({
            'judge_id':      jid,
            'n_judgments':   len(times),
            'mean_gap_s':    round(sum(plausible) / len(plausible), 1) if plausible else None,
            'very_fast_pct': round(
                sum(1 for g in gaps if g < 1) / len(gaps) * 100, 1
            ) if gaps else 0,
            'very_slow_pct': round(
                sum(1 for g in gaps if g > 600) / len(gaps) * 100, 1
            ) if gaps else 0,
        })

    prompt = (
        "Analyse the labeling effort statistics below (NO item content is present). "
        "Identify anomalies (e.g. judges submitting faster than humanly possible, "
        "or extremely long pauses suggesting distraction). "
        "Do NOT assign or suggest labels.\n\n"
        f"Per-judge stats:\n{json.dumps(stats, indent=2)}\n\n"
        "Return JSON with keys:\n"
        "  anomalies: [{judge_id, reason}]\n"
        "  fatigue_signals: [{judge_id, reason}]\n"
        "  summary: string"
    )

    result = llm_call(prompt, prompt_version="effort-estimation-v1")
    return {
        'per_judge': stats,
        'analysis':  result.text,
        'llm_meta':  result.to_dict(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 3. Intra-judge consistency audit
#    Input:  list of {judge_id, item_id, label, bucket} dicts
#            where bucket = some categorical feature of the item (NOT the text)
#    Output: per-judge consistency report
# ─────────────────────────────────────────────────────────────────────────────
def intra_judge_consistency(judgments: list[dict]) -> dict[str, Any]:
    """
    Check whether each judge assigns labels consistently across items
    that share the same 'bucket' (a categorical feature from the dataset).
    """
    by_judge: dict[Any, dict[str, list[str]]] = defaultdict(lambda: defaultdict(list))
    for j in judgments:
        bucket = str(j.get('bucket', 'unknown'))
        by_judge[j['judge_id']][bucket].append(str(j['label']))

    per_judge_stats = []
    for jid, buckets in by_judge.items():
        inconsistent = []
        for bucket, labels in buckets.items():
            unique = set(labels)
            if len(unique) > 1:
                inconsistent.append({'bucket': bucket, 'labels': list(unique)})
        per_judge_stats.append({
            'judge_id':     jid,
            'total_items':  sum(len(v) for v in buckets.values()),
            'inconsistent_buckets': len(inconsistent),
            'examples':     inconsistent[:5],
        })

    prompt = (
        "Audit intra-judge consistency. For each judge, report whether they assign "
        "different labels to items that share the same feature bucket — which may "
        "indicate drift, fatigue, or misunderstanding of the codebook. "
        "Do NOT suggest what the correct label should be.\n\n"
        f"Data:\n{json.dumps(per_judge_stats, indent=2)}\n\n"
        "Return JSON with keys:\n"
        "  flagged_judges: [{judge_id, severity: 'high'|'medium'|'low', reason}]\n"
        "  summary: string"
    )

    result = llm_call(prompt, prompt_version="intra-consistency-v1")
    return {
        'per_judge': per_judge_stats,
        'analysis':  result.text,
        'llm_meta':  result.to_dict(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 4. Codebook induction
#    Input:  label frequency dict {label_string: count}
#    Output: suggested codebook with definitions
# ─────────────────────────────────────────────────────────────────────────────
def codebook_induction(label_counts: dict[str, int]) -> dict[str, Any]:
    """
    From the label distribution, infer a draft codebook with definitions
    for each label. Judges' decisions are NOT shown; only counts are exposed.
    """
    sorted_labels = sorted(label_counts.items(), key=lambda x: -x[1])

    prompt = (
        "You are a methodology expert helping teams create labeling codebooks. "
        "You are given the label strings that judges have been using and how often. "
        "You do NOT know what items received which labels — only the vocabulary.\n\n"
        f"Label frequency table:\n{json.dumps(dict(sorted_labels), indent=2)}\n\n"
        "Tasks:\n"
        "1. Identify potential duplicates or near-synonyms.\n"
        "2. Suggest canonical label names.\n"
        "3. Draft a one-sentence definition for each canonical label.\n"
        "4. Flag any labels that seem like noise or typos.\n\n"
        "Return JSON with keys:\n"
        "  canonical_labels: [{original, canonical, definition}]\n"
        "  suspected_duplicates: [[label_a, label_b, reason]]\n"
        "  noise_labels: [label]\n"
        "  codebook_markdown: string"
    )

    result = llm_call(prompt, prompt_version="codebook-induction-v1")
    return {
        'label_counts': dict(sorted_labels),
        'analysis':     result.text,
        'llm_meta':     result.to_dict(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 5. Threats-to-validity report
#    Input:  evaluation summary dict (status, n_judges, n_items, kappa pairs…)
#    Output: structured threats-to-validity checklist
# ─────────────────────────────────────────────────────────────────────────────
def threats_to_validity(eval_summary: dict[str, Any]) -> dict[str, Any]:
    """
    Produce a threats-to-validity report based on study-level statistics,
    not on individual item content.
    """
    prompt = (
        "You are a research methodology expert. "
        "Given the study-level statistics below, identify threats to construct, "
        "internal, and external validity. Do NOT look at individual item content "
        "or assign labels.\n\n"
        f"Study summary:\n{json.dumps(eval_summary, indent=2)}\n\n"
        "Return JSON with keys:\n"
        "  construct_validity: [{threat, severity: 'high'|'medium'|'low', mitigation}]\n"
        "  internal_validity:  [{threat, severity, mitigation}]\n"
        "  external_validity:  [{threat, severity, mitigation}]\n"
        "  overall_confidence: 'high'|'medium'|'low'\n"
        "  executive_summary:  string"
    )

    result = llm_call(prompt, prompt_version="threats-validity-v1")
    return {
        'eval_summary': eval_summary,
        'analysis':     result.text,
        'llm_meta':     result.to_dict(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# 6. Semantic label normalisation
#    Input:  list of raw label strings
#    Output: normalisation map {raw_label → canonical_label}
# ─────────────────────────────────────────────────────────────────────────────
def semantic_label_normalisation(labels: list[str]) -> dict[str, Any]:
    """
    Detect when different surface forms of labels mean the same thing
    (e.g. "pos", "positive", "POS", "1").

    SAFETY: This function only receives label strings, never item content.
    The returned normalisation map is advisory — humans must approve it
    before any re-labeling action is taken.
    """
    unique_labels = sorted(set(labels))

    prompt = (
        "You are a data-cleaning assistant. "
        "Given a list of label strings from a labeling study, identify groups of "
        "strings that are semantically equivalent (e.g. case variants, abbreviations, "
        "synonym forms). "
        "Return a normalisation mapping so the owner can review and apply it manually. "
        "Do NOT apply the mapping — just suggest it.\n\n"
        f"Unique labels seen:\n{json.dumps(unique_labels, indent=2)}\n\n"
        "Return JSON with keys:\n"
        "  groups: [{canonical, variants: [list], confidence: 'high'|'medium'|'low'}]\n"
        "  normalisation_map: {raw_label: canonical_label}\n"
        "  unmapped: [labels_that_could_not_be_grouped]"
    )

    result = llm_call(prompt, prompt_version="label-normalisation-v1")
    return {
        'unique_labels': unique_labels,
        'analysis':      result.text,
        'llm_meta':      result.to_dict(),
    }

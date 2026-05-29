"""
Phase 9 — Guided Tutorial Mode.

Usage:
    python manage.py seed_tutorial [--username demo] [--password demo1234]

Creates:
  • A demo owner account ("demo") plus 2 judge accounts ("judge1", "judge2")
  • A tiny in-memory dataset (10 movie-sentiment rows) — no file upload needed
  • An Evaluation "Tutorial Evaluation" in 'open' status
  • Pre-seeded judgments for judge1 and judge2 so κ is immediately computable

SAFETY: Does NOT pre-label any item for the demo user — the tutorial teaches
the owner role, not the judge role.
"""
from __future__ import annotations

from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from django.db import transaction

from core.models import Dataset, DatasetColumn, DatasetItem, Evaluation


DEMO_ROWS = [
    ("I loved every minute of this film!", "positive"),
    ("A complete waste of time.", "negative"),
    ("Brilliant performances all around.", "positive"),
    ("The plot made no sense whatsoever.", "negative"),
    ("Surprisingly touching and well-crafted.", "positive"),
    ("Boring, predictable, and overly long.", "negative"),
    ("One of the best films I've seen this year.", "positive"),
    ("The dialogue was cringe-worthy.", "negative"),
    ("A masterpiece of modern cinema.", "positive"),
    ("I fell asleep halfway through.", "negative"),
]


class Command(BaseCommand):
    help = "Seed the database with a tutorial evaluation (Phase 9)."

    def add_arguments(self, parser):
        parser.add_argument("--username", default="demo",    help="Owner username")
        parser.add_argument("--password", default="demo1234", help="Owner password")
        parser.add_argument("--force",    action="store_true",
                            help="Re-seed even if tutorial data already exists.")

    @transaction.atomic
    def handle(self, *args, **options):
        username = options["username"]
        password = options["password"]
        force    = options["force"]

        # ── Guard against double-seeding ────────────────────────────────────
        if Evaluation.objects.filter(name="Tutorial Evaluation").exists():
            if not force:
                self.stdout.write(self.style.WARNING(
                    "Tutorial data already exists. Use --force to re-seed."))
                return
            Evaluation.objects.filter(name="Tutorial Evaluation").delete()

        # ── Accounts ────────────────────────────────────────────────────────
        owner, _ = User.objects.get_or_create(username=username)
        owner.set_password(password)
        owner.save()

        judge1, _ = User.objects.get_or_create(username="judge1")
        judge1.set_password("judge1pass")
        judge1.save()

        judge2, _ = User.objects.get_or_create(username="judge2")
        judge2.set_password("judge2pass")
        judge2.save()

        self.stdout.write(f"  Users: {owner} / {judge1} / {judge2}")

        # ── Dataset ─────────────────────────────────────────────────────────
        ds = Dataset.objects.create(
            created_by=owner,
            name="Tutorial Movie Sentiments",
            version=1,
            delimiter=",",
            encoding="UTF-8",
            original_file="",  # no file on disk — tutorial dataset is in-memory
        )
        DatasetColumn.objects.create(
            dataset=ds,
            name_in_file="review", mapped_name="review",
            role="TEXT",
        )
        DatasetColumn.objects.create(
            dataset=ds,
            name_in_file="sentiment", mapped_name="sentiment",
            role="LABEL",
        )

        items = []
        for i, (review, sentiment) in enumerate(DEMO_ROWS):
            item = DatasetItem.objects.create(
                dataset=ds,
                row_index=i,
                data={"review": review, "sentiment": sentiment},
            )
            items.append(item)

        self.stdout.write(f"  Dataset #{ds.id} with {len(items)} items.")

        # ── Evaluation ──────────────────────────────────────────────────────
        ev = Evaluation.objects.create(
            owner=owner,
            dataset=ds,
            name="Tutorial Evaluation",
            status="open",
        )
        ev.judges.set([judge1, judge2])
        ev.save()

        self.stdout.write(f"  Evaluation #{ev.id} created.")

        # ── Pre-seeded judgments (diverse enough to get a real κ) ────────────
        # SAFETY: These are from "judge1" and "judge2", NOT from the demo owner.
        # The demo owner sees the evaluation as an owner, not as a judge.
        from core.models import Judgment

        # judge1 — mostly correct, one deliberate disagreement
        j1_labels = ["positive","negative","positive","negative",
                     "positive","negative","positive","negative","positive","negative"]
        # judge2 — mostly correct, a couple of deliberate disagreements
        j2_labels = ["positive","negative","positive","positive",
                     "positive","negative","negative","negative","positive","negative"]

        for dataset_item, label in zip(items, j1_labels):
            Judgment.objects.create(
                evaluation=ev,
                item=dataset_item,
                judge=judge1,
                value=label,
                confidence=0.9,
            )
        for dataset_item, label in zip(items, j2_labels):
            Judgment.objects.create(
                evaluation=ev,
                item=dataset_item,
                judge=judge2,
                value=label,
                confidence=0.85,
            )

        self.stdout.write(self.style.SUCCESS(
            f"\nTutorial seeded!\n"
            f"  Owner:  {username} / {password}\n"
            f"  Judge1: judge1 / judge1pass\n"
            f"  Judge2: judge2 / judge2pass\n"
            f"  Evaluation ID: {ev.id}  (status: open)\n"
        ))

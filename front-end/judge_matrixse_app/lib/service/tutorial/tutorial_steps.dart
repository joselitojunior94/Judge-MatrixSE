import 'package:flutter/material.dart';

enum TutorialTarget {
  appTitle,
  homeHero,
  datasetNav,
  datasetWizard,
  evaluationsNav,
  evaluationsToolbar,
  evaluationActions,
  peopleNav,
  profileNav,
  rankingsNav,
  accountMenu,
}

class TutorialStep {
  const TutorialStep({
    required this.title,
    required this.body,
    required this.target,
    required this.screenIndex,
    required this.icon,
    this.primaryLabel = 'Next',
  });

  final String title;
  final String body;
  final TutorialTarget target;
  final int screenIndex;
  final IconData icon;
  final String primaryLabel;
}

const tutorialSteps = <TutorialStep>[
  TutorialStep(
    title: 'Welcome to the command center',
    body:
        'This guided overlay walks through the live glass workspace. It opens automatically the first time you use the tool, and you can skip it at any time.',
    target: TutorialTarget.appTitle,
    screenIndex: 0,
    icon: Icons.school_outlined,
  ),
  TutorialStep(
    title: 'Start from the Dataset rail',
    body:
        'The command sidebar groups the real workflow. Use Datasets to upload CSV files, preview rows, and map columns to roles such as ID, Text, Label, Feature, or Ignore.',
    target: TutorialTarget.datasetNav,
    screenIndex: 1,
    icon: Icons.upload_file_outlined,
  ),
  TutorialStep(
    title: 'Use the illuminated wizard',
    body:
        'The wizard is the first real workflow: choose a file, inspect the preview, confirm column roles, and review label normalization when a pre-existing Label column is present.',
    target: TutorialTarget.datasetWizard,
    screenIndex: 1,
    icon: Icons.table_chart_outlined,
  ),
  TutorialStep(
    title: 'Move into evaluations',
    body:
        'Evaluations sit in the Workflow group. They bind a dataset to a labeling study where owners add judges, reviewers, and viewers before opening the work.',
    target: TutorialTarget.evaluationsNav,
    screenIndex: 2,
    icon: Icons.fact_check_outlined,
  ),
  TutorialStep(
    title: 'Launch a study',
    body:
        'This primary action starts a real creation flow. Pick a dataset, name the study, drag people into roles, then review the effort-routing suggestion before labeling begins.',
    target: TutorialTarget.evaluationsToolbar,
    screenIndex: 2,
    icon: Icons.add_circle_outline,
  ),
  TutorialStep(
    title: 'Use the action cluster',
    body:
        'Each row exposes real actions: details, items, metrics, results, and AI meta-evaluation. Details includes member editing, lifecycle controls, and the owner-reviewed codebook draft.',
    target: TutorialTarget.evaluationActions,
    screenIndex: 2,
    icon: Icons.rule_folder_outlined,
  ),
  TutorialStep(
    title: 'AI stays behind the glass',
    body:
        'AI is only a meta-evaluation layer: label normalization in the wizard, routing in setup, codebook drafts during labeling, disagreement diagnosis in results, consistency auditing, and validity reports on closure. It never casts human labels.',
    target: TutorialTarget.evaluationActions,
    screenIndex: 2,
    icon: Icons.smart_toy_outlined,
  ),
  TutorialStep(
    title: 'Find collaborators',
    body:
        'People is the collaborator directory. Search by name or username, open public profiles, follow collaborators, or add someone directly to an evaluation role.',
    target: TutorialTarget.peopleNav,
    screenIndex: 4,
    icon: Icons.groups_2_outlined,
  ),
  TutorialStep(
    title: 'Build your academic profile',
    body:
        'Profile is your own academic identity: photo, links, ORCID publications, badges, points, followers, and following.',
    target: TutorialTarget.profileNav,
    screenIndex: 5,
    icon: Icons.person_outline,
  ),
  TutorialStep(
    title: 'Track gamified activity',
    body:
        'Rankings links activity to public profiles and scrolls through platform and per-evaluation leaderboards, including total activity inside an evaluation.',
    target: TutorialTarget.rankingsNav,
    screenIndex: 6,
    icon: Icons.emoji_events_outlined,
  ),
  TutorialStep(
    title: 'You are ready',
    body:
        'You can now upload a dataset, create an evaluation, judge items, review judgments, publish a codebook, inspect metrics, diagnose disagreements, export results, and close with a validity report.',
    target: TutorialTarget.accountMenu,
    screenIndex: 0,
    icon: Icons.check_circle_outline,
    primaryLabel: 'Finish',
  ),
];

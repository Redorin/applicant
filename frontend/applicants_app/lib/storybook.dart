// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import 'storybook/stories/applicant_card_story.dart';
import 'storybook/stories/status_pill_story.dart';
import 'storybook/stories/dashboard_tile_story.dart';
import 'storybook/stories/form_field_story.dart';

void main() => runApp(const StoryBookApp());

class StoryBookApp extends StatelessWidget {
  const StoryBookApp({super.key});

  @override
  Widget build(BuildContext context) => Storybook(
        stories: [
          ...applicantCardStories,
          ...statusPillStories,
          ...dashboardTileStories,
          ...formFieldStories,
        ],
      );
}

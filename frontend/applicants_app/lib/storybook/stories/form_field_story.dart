// ignore_for_file: depend_on_referenced_packages
import 'package:flutter/material.dart';
import 'package:storybook_flutter/storybook_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_typography.dart';

final formFieldStories = [
  Story(
    name: 'Form Field / Text Input',
    builder: (context) => SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Full Name'),
          const SizedBox(height: 4),
          TextField(
            decoration: _fieldDecoration(hint: 'Enter full name'),
          ),
        ],
      ),
    ),
  ),
  Story(
    name: 'Form Field / Dropdown',
    builder: (context) => SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Status'),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            decoration: _fieldDecoration(hint: 'Select status'),
            items: const [
              DropdownMenuItem(value: 'Active File', child: Text('Active File')),
              DropdownMenuItem(value: 'On Process', child: Text('On Process')),
              DropdownMenuItem(value: 'Hired', child: Text('Hired')),
              DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
            ],
            onChanged: (_) {},
          ),
        ],
      ),
    ),
  ),
  Story(
    name: 'Form Field / Search',
    builder: (context) => SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Search'),
          const SizedBox(height: 4),
          TextField(
            decoration: _fieldDecoration(
              hint: 'Search applicants...',
              prefixIcon: const Icon(Icons.search, size: 16, color: AppColors.muted),
            ),
          ),
        ],
      ),
    ),
  ),
  Story(
    name: 'Form Field / States',
    builder: (context) => SizedBox(
      width: 300,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('Normal'),
          const SizedBox(height: 4),
          TextField(decoration: _fieldDecoration(hint: 'Normal field')),
          const SizedBox(height: 16),
          _label('Error'),
          const SizedBox(height: 4),
          TextField(
            decoration: _fieldDecoration(hint: 'Error field')
                .copyWith(errorText: 'This field is required'),
          ),
          const SizedBox(height: 16),
          _label('Disabled'),
          const SizedBox(height: 4),
          TextField(
            enabled: false,
            decoration: _fieldDecoration(hint: 'Disabled field'),
          ),
        ],
      ),
    ),
  ),
];

Widget _label(String text) => Text(
      text,
      style: AppTypography.helper.copyWith(color: AppColors.muted),
    );

InputDecoration _fieldDecoration({
  required String hint,
  Widget? prefixIcon,
}) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: prefixIcon,
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: AppRadius.smAll,
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.smAll,
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.smAll,
        borderSide:
            const BorderSide(color: AppColors.selectedBorder, width: 1.4),
      ),
    );

import 'package:flutter/material.dart';

/// One entry in the sidebar — shared between [SidebarRail] and
/// [SidebarDrawer] so the two surfaces can never list different items or
/// disagree on paths/icons.
class SidebarNavItem {
  const SidebarNavItem(this.label, this.icon, this.path);
  final String label;
  final IconData icon;
  final String path;
}

const sidebarNavItems = [
  SidebarNavItem('Dashboard', Icons.home, '/dashboard'),
  SidebarNavItem('Master Data', Icons.person, '/master-data'),
  SidebarNavItem('List of Applicants', Icons.reorder, '/list'),
  SidebarNavItem('Hired Applicants', Icons.check, '/hired'),
  SidebarNavItem('Summary Reports', Icons.bar_chart, '/reports'),
  SidebarNavItem('Data Health', Icons.health_and_safety, '/data-health'),
  SidebarNavItem('Activity Logs', Icons.receipt_long, '/logs'),
];

/// Index (0-based) after which the divider renders — between "Hired
/// Applicants" and "Summary Reports" — read by both rail and drawer so the
/// divider can't end up in different spots on the two surfaces.
const dividerAfterIndex = 3;

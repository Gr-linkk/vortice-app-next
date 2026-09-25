import 'package:flutter/material.dart';
import 'app_navigation.dart';
import 'theme.dart';

/// One workspace: compact navigation in the field, labelled navigation at a desk.
class WorkspaceLayout extends StatelessWidget {
  const WorkspaceLayout({
    super.key,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.child,
    required this.compactNavigation,
    required this.spanish,
    required this.french,
    this.hideNavigation = false,
  });
  final List<AppDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Widget child, compactNavigation;
  final bool spanish, french, hideNavigation;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final wide =
          size.maxWidth >= 1000 &&
          MediaQuery.textScalerOf(context).scale(1) < 1.8;
      if (!wide) {
        return Scaffold(
          body: child,
          bottomNavigationBar: hideNavigation ? null : compactNavigation,
        );
      }
      return Row(
        children: [
          if (!hideNavigation) ...[
            SizedBox(
              width: 240,
              child: Material(
                color: context.appColors.surfaceVariant,
                child: SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      vertical: 24,
                      horizontal: 12,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 30),
                        child: Text(
                          'Vortice Next',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      for (var index = 0; index < destinations.length; index++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            selected: selectedIndex == index,
                            selectedTileColor: context.appColors.primary
                                .withValues(alpha: .1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            leading: Icon(destinations[index].icon),
                            title: Text(
                              destinations[index].label(
                                spanish,
                                french: french,
                              ),
                            ),
                            onTap: () => onSelect(index),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            VerticalDivider(width: 1, color: context.appColors.divider),
          ],
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: child,
              ),
            ),
          ),
        ],
      );
    },
  );
}

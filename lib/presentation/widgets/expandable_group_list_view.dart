import 'package:boorusphere/presentation/utils/extensions/buildcontext.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

class ExpandableGroupListView<T, E> extends StatelessWidget {
  const ExpandableGroupListView({
    super.key,
    required this.items,
    required this.groupedBy,
    required this.groupTitle,
    required this.itemBuilder,
    this.expanded = true,
    this.ungroup = false,
  });

  final List<T> items;
  final E Function(T entry) groupedBy;
  final Widget Function(E key) groupTitle;
  final Widget Function(T entry) itemBuilder;
  final bool ungroup;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    if (ungroup) {
      return ListView.builder(
        padding: const EdgeInsets.only(bottom: 48),
        itemCount: items.length,
        itemBuilder: (context, index) => itemBuilder(items.atReverse(index)),
      );
    }

    // Group once per build instead of per-item-tile (the previous getter
    // was invoked from both `itemCount` and `itemBuilder`, doing the work
    // 1 + N times each rebuild) and reverse the entries up-front so we
    // index a List directly.
    final groups = groupBy(items, groupedBy).entries.toList().reversed.toList();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 48),
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return Theme(
          data: context.theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: groupTitle(group.key),
            initiallyExpanded: expanded,
            textColor: context.colorScheme.onSurface,
            children: group.value.map(itemBuilder).toList(growable: false),
          ),
        );
      },
    );
  }
}

extension _IterableExt<T> on Iterable<T> {
  T atReverse(int index) {
    return elementAt(length - index - 1);
  }
}

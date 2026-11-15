/// Predicts the one-based position within the destination group produced by
/// the tab manager's drop logic without mutating the live tab list.
int predictedTabDropPosition({
  required List<String?> tabGroupIds,
  required int draggedIndex,
  required String? targetGroupId,
  int? targetIndex,
}) {
  if (draggedIndex < 0 || draggedIndex >= tabGroupIds.length) {
    return 1;
  }

  final sourceGroupId = tabGroupIds[draggedIndex];
  if (targetIndex != null && targetIndex >= 0 && targetIndex < tabGroupIds.length) {
    var positionInGroup = 0;
    for (var index = 0; index <= targetIndex; index++) {
      if (tabGroupIds[index] == targetGroupId) {
        positionInGroup++;
      }
    }
    return positionInGroup == 0 ? 1 : positionInGroup;
  }

  if (sourceGroupId == targetGroupId) {
    var positionInGroup = 0;
    for (var index = 0; index <= draggedIndex; index++) {
      if (tabGroupIds[index] == targetGroupId) {
        positionInGroup++;
      }
    }
    return positionInGroup == 0 ? 1 : positionInGroup;
  }

  // Header drops append to the destination group.
  return tabGroupIds.where((groupId) => groupId == targetGroupId).length + 1;
}

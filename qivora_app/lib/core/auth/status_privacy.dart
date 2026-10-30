/// Centralized status privacy rule checker.
/// Applied whenever statuses are loaded or accessed.
bool canViewStatus({
  required String ownerId,
  required String viewerId,
  required String privacy,
  required Set<String> contacts,
  Set<String>? except,
  Set<String>? only,
}) {
  // The owner can always view their own status.
  if (viewerId == ownerId) return true;

  if (privacy == 'contacts') {
    return contacts.contains(viewerId);
  }
  if (privacy == 'except') {
    return contacts.contains(viewerId) && !(except ?? {}).contains(viewerId);
  }
  if (privacy == 'only') {
    return (only ?? {}).contains(viewerId);
  }
  // Default: everyone.
  return true;
}

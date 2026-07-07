import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/services/server_favorite_feedback.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class ServerFavoriteRequestsPage extends StatelessWidget {
  const ServerFavoriteRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SettingsAppBar(title: context.loc.serverFavouritesSync.sessionRequests),
      body: ValueListenableBuilder<List<ServerFavoriteRequestLogEntry>>(
        valueListenable: ServerFavoriteFeedback.requests,
        builder: (context, entries, _) {
          return ListView(
            children: [
              SettingsButton(
                name: context.loc.serverFavouritesSync.clearSessionRequests,
                icon: const Icon(Icons.clear_all),
                enabled: entries.isNotEmpty,
                action: entries.isEmpty ? null : ServerFavoriteFeedback.clear,
              ),
              SettingsButton(
                name: context.loc.serverFavouritesSync.requestListSubtitle(count: entries.length),
                enabled: false,
              ),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(context.loc.serverFavouritesSync.sessionRequestsEmpty),
                )
              else
                ...entries.map(_RequestTile.new),
            ],
          );
        },
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  const _RequestTile(this.entry);

  final ServerFavoriteRequestLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final loc = context.loc.serverFavouritesSync;
    final statusText = entry.status == ServerFavoriteRequestStatus.success
        ? loc.requestStatusSuccess
        : loc.requestStatusFailed;
    final actionText = entry.action == ServerFavoriteRequestAction.add ? loc.requestActionAdd : loc.requestActionRemove;

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 48,
          height: 48,
          child: entry.item.thumbnailURL.isEmpty
              ? const Icon(Icons.favorite)
              // TODO replace with thumbnail
              : Image.network(
                  entry.item.thumbnailURL,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(Icons.favorite),
                ),
        ),
      ),
      title: Text('$actionText: ${entry.booruName}'),
      subtitle: Text(
        [
          '$statusText | ${entry.serverId}',
          entry.timestamp.toLocal().toString(),
          if (entry.message?.isNotEmpty == true) entry.message!,
        ].join('\n'),
      ),
      trailing: Icon(
        entry.status == ServerFavoriteRequestStatus.success ? Icons.check_circle : Icons.error,
        color: entry.status == ServerFavoriteRequestStatus.success
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
  }
}

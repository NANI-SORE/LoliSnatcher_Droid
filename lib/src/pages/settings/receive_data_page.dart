import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_device_info.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_discovery_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_formatters.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_history_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_socket_client.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class ReceiveDataPage extends StatefulWidget {
  const ReceiveDataPage({super.key});

  @override
  State<ReceiveDataPage> createState() => _ReceiveDataPageState();
}

class _ReceiveDataPageState extends State<ReceiveDataPage> with WidgetsBindingObserver {
  final discovery = TransferDiscoveryService();
  final client = TransferSocketClient();
  final registry = BackupEntryRegistry.instance;
  final historyService = const TransferHistoryService();
  final logs = <BackupTransferLog>[];
  List<DiscoveredTransferDevice> devices = [];
  List<TransferHistoryEntry> history = [];
  BackupTransferStats? stats;
  StreamSubscription<List<DiscoveredTransferDevice>>? devicesSub;
  StreamSubscription<BackupTransferLog>? logSub;
  StreamSubscription<BackupTransferStats>? statsSub;
  bool receiving = false;
  bool keepAwake = false;
  String ip = '';
  String deviceName = '';
  String deviceId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    devicesSub = discovery.devices.listen((newDevices) {
      if (!mounted) return;
      setState(() => devices = newDevices);
    });
    logSub = client.logs.stream.listen((log) {
      if (!mounted) return;
      setState(() => logs.insert(0, log));
    });
    statsSub = client.stats.stream.listen((newStats) {
      if (!mounted) return;
      setState(() => stats = newStats);
    });
    unawaited(_loadDeviceInfoAndStartDiscovery());
    unawaited(_loadHistory());
  }

  Future<void> _loadDeviceInfoAndStartDiscovery() async {
    final nextIp = await ServiceHandler.getIP();
    final nextDeviceName = await TransferDeviceInfo.displayName();
    final nextDeviceId = await TransferDeviceInfo.instanceId();
    if (!mounted) return;
    setState(() {
      ip = nextIp;
      deviceName = nextDeviceName;
      deviceId = nextDeviceId;
    });
    await discovery.startDiscovery(
      ignoredDeviceId: nextDeviceId,
      ignoredHosts: {nextIp},
    );
  }

  Future<void> _loadHistory() async {
    final entries = await historyService.load();
    if (!mounted) return;
    setState(() => history = entries.where((entry) => entry.direction == TransferHistoryDirection.received).toList());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setKeepAwake(false);
    devicesSub?.cancel();
    logSub?.cancel();
    statsSub?.cancel();
    unawaited(discovery.dispose());
    unawaited(client.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && keepAwake) {
      ServiceHandler.disableSleep(force: true);
    }
  }

  void _setKeepAwake(bool value) {
    if (keepAwake == value) return;
    keepAwake = value;
    if (keepAwake) {
      ServiceHandler.disableSleep(force: true);
    } else {
      ServiceHandler.enableSleep();
    }
  }

  Future<void> _addManual() async {
    final controller = TextEditingController();
    final address = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.loc.settings.backupAndTransfer.addDevice),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'IP:port'),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp('[0-9.:]'))],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.loc.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(context.loc.add),
          ),
        ],
      ),
    );
    if (address == null || !address.contains(':')) return;
    final parts = address.split(':');
    final port = int.tryParse(parts.last);
    if (port == null) return;
    setState(() {
      devices = [
        ...devices,
        DiscoveredTransferDevice(
          id: address,
          name: context.loc.settings.backupAndTransfer.manualDevice,
          host: parts.first,
          port: port,
          version: context.loc.settings.backupAndTransfer.unknown,
          build: null,
          deviceId: null,
          isManual: true,
        ),
      ];
    });
  }

  Future<void> _selectAndReceive(DiscoveredTransferDevice device) async {
    final selected = <BackupEntryId>{};
    var tabsMode = BackupTabsMode.merge;
    final favouritesStartController = TextEditingController(text: '0');
    final snatchedStartController = TextEditingController(text: '0');
    final result = await showDialog<_ReceiveSelection>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(device.name),
              insetPadding: const EdgeInsets.all(12),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in registry.defaultEntries.where(
                      (entry) =>
                          entry.id != BackupEntryRegistry.databaseParentId && !registry.isDatabaseChild(entry.id),
                    ))
                      CheckboxListTile(
                        value: selected.contains(entry.id),
                        title: Text(entry.title()),
                        subtitle: Text(entry.description()),
                        onChanged: (value) {
                          setDialogState(() {
                            if (value == true) {
                              selected.add(entry.id);
                            } else {
                              selected.remove(entry.id);
                            }
                          });
                        },
                      ),
                    _DatabaseEntryTree(
                      registry: registry,
                      selected: selected,
                      onChanged: (entryId, value) {
                        setDialogState(() {
                          _setTreeEntrySelected(selected, entryId, value);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (_isEntrySelected(selected, BackupEntryId.tabs) &&
                        !_isEntrySelected(selected, BackupEntryId.database))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: DropdownButtonFormField<BackupTabsMode>(
                          initialValue: tabsMode,
                          decoration: InputDecoration(labelText: registry.byId(BackupEntryId.tabs).title()),
                          items: [
                            DropdownMenuItem(value: BackupTabsMode.merge, child: Text(context.loc.settings.sync.merge)),
                            DropdownMenuItem(
                              value: BackupTabsMode.replace,
                              child: Text(context.loc.settings.sync.replace),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setDialogState(() => tabsMode = value);
                          },
                        ),
                      ),
                    if (_isEntrySelected(selected, BackupEntryId.favourites) &&
                        !_isEntrySelected(selected, BackupEntryId.database))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: favouritesStartController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.loc.settings.sync.syncFavsFrom,
                          ),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                    if (_isEntrySelected(selected, BackupEntryId.snatched) &&
                        !_isEntrySelected(selected, BackupEntryId.database))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: snatchedStartController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: context.loc.settings.sync.syncSnatchedFrom,
                          ),
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(context.loc.cancel),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(
                          _ReceiveSelection(
                            entries: _normalizedSelectedEntries(selected),
                            tabsMode: tabsMode,
                            favouritesStartIndex: int.tryParse(favouritesStartController.text) ?? 0,
                            snatchedStartIndex: int.tryParse(snatchedStartController.text) ?? 0,
                          ),
                        ),
                  child: Text(context.loc.settings.backupAndTransfer.receive),
                ),
              ],
            );
          },
        );
      },
    );
    if (result == null || result.entries.isEmpty) return;

    setState(() => receiving = true);
    _setKeepAwake(true);
    try {
      await client.receive(
        host: device.host,
        port: device.port,
        entries: result.entries,
        receiverName: deviceName,
        senderName: device.name,
        senderAddress: device.address,
        transferOptions: {
          'favouritesStartIndex': result.favouritesStartIndex,
          'snatchedStartIndex': result.snatchedStartIndex,
        },
        options: BackupImportOptions(tabsMode: result.tabsMode),
      );
    } finally {
      _setKeepAwake(false);
      unawaited(_loadHistory());
      if (mounted) setState(() => receiving = false);
    }
  }

  void _setTreeEntrySelected(Set<BackupEntryId> selected, BackupEntryId entryId, bool value) {
    if (entryId == BackupEntryRegistry.databaseParentId) {
      if (value) {
        selected.add(BackupEntryRegistry.databaseParentId);
        selected.removeAll(BackupEntryRegistry.databaseChildIds);
      } else {
        selected.remove(BackupEntryRegistry.databaseParentId);
        selected.removeAll(BackupEntryRegistry.databaseChildIds);
      }
      return;
    }

    if (selected.contains(BackupEntryRegistry.databaseParentId)) return;

    if (value) {
      selected.add(entryId);
    } else {
      selected.remove(entryId);
    }

    if (selected.containsAll(BackupEntryRegistry.databaseChildIds) &&
        !selected.contains(BackupEntryRegistry.databaseParentId)) {
      selected.add(BackupEntryRegistry.databaseParentId);
      selected.removeAll(BackupEntryRegistry.databaseChildIds);
    }
  }

  bool _isEntrySelected(Set<BackupEntryId> selected, BackupEntryId entryId) {
    return selected.contains(entryId) || selected.contains(BackupEntryRegistry.databaseParentId);
  }

  List<BackupEntryId> _normalizedSelectedEntries(Set<BackupEntryId> selected) {
    final ordered = <BackupEntryId>[];
    for (final entry in registry.defaultEntries) {
      if (selected.contains(entry.id)) {
        ordered.add(entry.id);
      }
    }
    return ordered;
  }

  Future<void> _cancelReceive() async {
    await client.cancel();
    _setKeepAwake(false);
    if (!mounted) return;
    setState(() => receiving = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !receiving,
      child: Scaffold(
        appBar: SettingsAppBar(
          title: context.loc.settings.backupAndTransfer.receiveDataTitle,
          actions: [
            IconButton(
              icon: const Icon(Icons.cancel_outlined),
              tooltip: context.loc.cancel,
              onPressed: receiving ? _cancelReceive : null,
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              context.loc.settings.backupAndTransfer.deviceInfo,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  _InfoRow(
                    label: context.loc.settings.backupAndTransfer.name,
                    value: deviceName.isEmpty ? context.loc.settings.backupAndTransfer.starting : deviceName,
                  ),
                  _InfoRow(
                    label: context.loc.settings.backupAndTransfer.address,
                    value: ip.isEmpty ? context.loc.settings.backupAndTransfer.starting : ip,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            //
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.loc.settings.backupAndTransfer.nearbyDevices,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: context.loc.settings.backupAndTransfer.addDevice,
                  onPressed: receiving ? null : _addManual,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (devices.isEmpty) ListTile(title: Text(context.loc.settings.backupAndTransfer.noDevicesFound)),
            for (final device in devices)
              Card(
                child: ListTile(
                  title: Text(device.name),
                  subtitle: Text(
                    '${device.address} • ${device.version}${device.build != null ? ' (${device.build})' : ''}${device.isManual ? ' • ${context.loc.settings.backupAndTransfer.manual}' : ''}',
                  ),
                  trailing: const Icon(
                    Icons.chevron_right_rounded,
                    size: 24,
                  ),
                  onTap: receiving ? null : () => _selectAndReceive(device),
                ),
              ),
            //
            if (stats != null && stats!.isComplete != true) ...[
              const SizedBox(height: 12),
              Text(
                context.loc.settings.backupAndTransfer.transfer,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              ListTile(
                title: Text(context.loc.settings.backupAndTransfer.received),
                trailing: Text(_formatProgress(stats)),
              ),
              if (stats?.totalBytes != null)
                ListTile(
                  title: Text(context.loc.settings.backupAndTransfer.total),
                  trailing: Text(TransferFormatters.bytes(stats?.totalBytes ?? 0)),
                ),
              ListTile(
                title: Text(context.loc.settings.backupAndTransfer.elapsed),
                trailing: Text(
                  TransferFormatters.duration(DateTime.now().difference(stats?.startedAt ?? DateTime.now())),
                ),
              ),
              ListTile(
                title: Text(context.loc.settings.backupAndTransfer.speed),
                trailing: Text('${TransferFormatters.bytes(stats?.bytesPerSecond.round() ?? 0)}/s'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(context.loc.cancel),
                    onPressed: receiving ? _cancelReceive : null,
                  ),
                ),
              ),
            ],
            //
            if (logs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Text(context.loc.settings.backupAndTransfer.logs, style: Theme.of(context).textTheme.titleLarge),
              ),
            for (final indexedLog in logs.take(100).indexed)
              ListTile(
                dense: true,
                title: Text(indexedLog.$2.message),
                subtitle: Text(TransferFormatters.time(indexedLog.$2.createdAt)),
                trailing: _isLogRunning(indexedLog.$1)
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
            const SizedBox(height: 12),
            _HistorySection(history: history),
          ],
        ),
      ),
    );
  }

  String _formatProgress(BackupTransferStats? stats) {
    if (stats == null) return '';

    final transferred = TransferFormatters.bytes(stats.bytesTransferred);
    final total = stats.totalBytes;
    if (total == null || total <= 0) return transferred;
    final percent = stats.bytesTransferred / total * 100;
    return '$transferred / ${TransferFormatters.bytes(total)} (${percent.toStringAsFixed(1)}%)';
  }

  bool _isLogRunning(int index) {
    if (index != 0 || !receiving) return false;
    return stats?.isComplete != true;
  }
}

class _ReceiveSelection {
  const _ReceiveSelection({
    required this.entries,
    required this.tabsMode,
    required this.favouritesStartIndex,
    required this.snatchedStartIndex,
  });

  final List<BackupEntryId> entries;
  final BackupTabsMode tabsMode;
  final int favouritesStartIndex;
  final int snatchedStartIndex;
}

class _DatabaseEntryTree extends StatelessWidget {
  const _DatabaseEntryTree({
    required this.registry,
    required this.selected,
    required this.onChanged,
  });

  final BackupEntryRegistry registry;
  final Set<BackupEntryId> selected;
  final void Function(BackupEntryId entryId, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final database = registry.byId(BackupEntryRegistry.databaseParentId);
    final databaseSelected =
        selected.contains(BackupEntryRegistry.databaseParentId) ||
        selected.containsAll(BackupEntryRegistry.databaseChildIds);
    final childSelected = BackupEntryRegistry.databaseChildIds.any(selected.contains);
    final bool? databaseValue = databaseSelected
        ? true
        : childSelected
        ? null
        : false;

    return Column(
      children: [
        CheckboxListTile(
          tristate: true,
          value: databaseValue,
          title: Text(database.title()),
          subtitle: Text(database.description()),
          secondary: Icon(database.icon),
          onChanged: (_) => onChanged(database.id, !databaseSelected),
        ),
        for (final indexedEntry in BackupEntryRegistry.databaseChildIds.indexed)
          _DatabaseChildEntryTile(
            entry: registry.byId(indexedEntry.$2),
            isLast: indexedEntry.$1 == BackupEntryRegistry.databaseChildIds.length - 1,
            checked: databaseSelected || selected.contains(indexedEntry.$2),
            locked: databaseSelected,
            onChanged: (value) => onChanged(indexedEntry.$2, value),
          ),
      ],
    );
  }
}

class _DatabaseChildEntryTile extends StatelessWidget {
  const _DatabaseChildEntryTile({
    required this.entry,
    required this.isLast,
    required this.checked,
    required this.locked,
    required this.onChanged,
  });

  final BackupEntryDefinition entry;
  final bool isLast;
  final bool checked;
  final bool locked;
  final void Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).dividerColor;
    return Stack(
      children: [
        Positioned.directional(
          textDirection: Directionality.of(context),
          start: 0,
          top: 0,
          bottom: 0,
          width: 42,
          child: CustomPaint(
            painter: _TreeBranchPainter(color: color, isLast: isLast),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 42),
          child: CheckboxListTile(
            dense: true,
            value: checked,
            title: Text(entry.title()),
            subtitle: Text(entry.description()),
            secondary: Icon(entry.icon),
            onChanged: locked ? null : (value) => onChanged(value ?? false),
          ),
        ),
      ],
    );
  }
}

class _TreeBranchPainter extends CustomPainter {
  const _TreeBranchPainter({required this.color, required this.isLast});

  final Color color;
  final bool isLast;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final x = size.width * 0.62;
    final y = size.height / 2;
    canvas.drawLine(Offset(x, 0), Offset(x, isLast ? y : size.height), paint);
    canvas.drawLine(Offset(x, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(covariant _TreeBranchPainter oldDelegate) {
    return color != oldDelegate.color || isLast != oldDelegate.isLast;
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.history});

  final List<TransferHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.history, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (history.isEmpty)
          ListTile(title: Text(t.noHistory))
        else
          for (final entry in history.take(20))
            Card(
              child: ListTile(
                title: Text(entry.peerName.isEmpty ? entry.peerAddress : entry.peerName),
                subtitle: Text(
                  [
                    entry.peerAddress,
                    TransferFormatters.dateTime(entry.createdAt),
                    '${t.selectedData}: ${_entryNames(entry.entryIds)}',
                  ].where((line) => line.isNotEmpty).join('\n'),
                ),
                isThreeLine: true,
              ),
            ),
      ],
    );
  }

  String _entryNames(List<BackupEntryId> entryIds) {
    return entryIds.map((id) => BackupEntryRegistry.instance.byId(id).title()).join(', ');
  }
}

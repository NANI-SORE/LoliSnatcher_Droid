import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_device_info.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_discovery_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_formatters.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_history_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_socket_server.dart';
import 'package:lolisnatcher/src/widgets/common/flash_elements.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class SendDataPage extends StatefulWidget {
  const SendDataPage({super.key});

  @override
  State<SendDataPage> createState() => _SendDataPageState();
}

class _SendDataPageState extends State<SendDataPage> with WidgetsBindingObserver {
  final server = TransferSocketServer();
  final discovery = TransferDiscoveryService();
  final historyService = const TransferHistoryService();
  final logs = <BackupTransferLog>[];
  List<TransferHistoryEntry> history = [];
  BackupTransferStats? stats;
  StreamSubscription<BackupTransferLog>? logSub;
  StreamSubscription<BackupTransferStats>? statsSub;
  bool includeDeviceSpecificSettings = false;
  bool started = false;
  bool starting = false;
  String ip = '';
  String deviceName = '';
  String deviceId = '';
  bool keepAwake = false;

  bool get _hasActiveTransfer => started && stats != null && stats!.isComplete != true;

  bool get visible => SX.syncVisibleOnNetwork.state.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SX.syncVisibleOnNetwork.state.effectiveNotifier.addListener(_onVisibleChanged);

    logSub = server.logs.stream.listen((log) {
      if (!mounted) return;
      setState(() => logs.insert(0, log));
    });
    statsSub = server.stats.stream.listen((newStats) {
      if (!mounted) return;
      setState(() => stats = newStats);
      if (newStats.isComplete) unawaited(_loadHistory());
      if (newStats.isComplete && newStats.currentEntry == 'error') {
        unawaited(_stop());
      }
    });
    unawaited(_start());
    unawaited(_loadHistory());
  }

  void _onVisibleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadHistory() async {
    final entries = await historyService.load();
    if (!mounted) return;
    setState(() => history = entries.where((entry) => entry.direction == TransferHistoryDirection.sent).toList());
  }

  Future<void> _start() async {
    if (started || starting) return;
    if (mounted) {
      setState(() {
        starting = true;
        stats = null;
      });
    } else {
      starting = true;
      stats = null;
    }
    try {
      ip = await ServiceHandler.getIP();
      deviceName = await TransferDeviceInfo.displayName();
      deviceId = await TransferDeviceInfo.instanceId();
      await server.start(deviceName: deviceName);
      _setKeepAwake(true);
      started = true;
      if (visible) {
        await discovery.startBroadcast(deviceName: deviceName, deviceId: deviceId, port: server.port!);
      }
    } finally {
      starting = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _setVisible(bool value) async {
    SX.syncVisibleOnNetwork.state.value = value;
    await SettingsHandler.instance.saveSettings(restate: false);

    if (visible && started) {
      await discovery.startBroadcast(deviceName: deviceName, deviceId: deviceId, port: server.port!);
    } else {
      await discovery.stopBroadcast();
    }
    if (mounted) setState(() {});
  }

  void _setIncludeDeviceSpecificSettings(bool value) {
    includeDeviceSpecificSettings = value;
    server.includeDeviceSpecificSettings = value;
    if (mounted) setState(() {});
  }

  void _showDeviceSpecificSettingsHelp() {
    showDialog(
      context: context,
      builder: (dialogContext) => SettingsDialog(
        title: Text(dialogContext.loc.settings.backupAndTransfer.includeDeviceSpecificSettingsHelpTitle),
        contentItems: [
          Text(dialogContext.loc.settings.backupAndTransfer.includeDeviceSpecificSettingsHelp),
        ],
      ),
    );
  }

  Future<void> _stop() async {
    await discovery.stopBroadcast();
    await server.stop();
    _setKeepAwake(false);
    if (!mounted) return;
    setState(() {
      started = false;
      starting = false;
    });
  }

  Future<void> _cancelTransfer() async {
    await server.cancelTransfers();
    if (visible && started && server.port != null) {
      await discovery.startBroadcast(deviceName: deviceName, deviceId: deviceId, port: server.port!);
    }
    if (!mounted) return;
    setState(() => stats = null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SX.syncVisibleOnNetwork.state.effectiveNotifier.removeListener(_onVisibleChanged);
    _setKeepAwake(false);
    logSub?.cancel();
    statsSub?.cancel();
    unawaited(discovery.dispose());
    unawaited(server.dispose());
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

  @override
  Widget build(BuildContext context) {
    final port = server.port;
    final address = port == null ? null : '$ip:$port';
    return PopScope(
      canPop: !_hasActiveTransfer,
      child: Scaffold(
        appBar: SettingsAppBar(
          title: context.loc.settings.backupAndTransfer.sendDataTitle,
          actions: [
            IconButton(
              icon: Icon(
                started
                    ? (_hasActiveTransfer ? Icons.cancel_outlined : Icons.stop_circle_outlined)
                    : Icons.play_circle_outline,
              ),
              tooltip: started ? context.loc.media.loading.stopLoading : context.loc.settings.backupAndTransfer.send,
              onPressed: started
                  ? (_hasActiveTransfer ? _cancelTransfer : _stop)
                  : starting
                  ? null
                  : _start,
            ),
          ],
        ),
        body: ListView(
          children: [
            const SizedBox(height: 12),
            Column(
              children: [
                SwitchListTile(
                  title: Text(context.loc.settings.backupAndTransfer.visibleOnNetwork),
                  subtitle: Text(context.loc.settings.backupAndTransfer.visibleOnNetworkSubtitle),
                  value: visible,
                  onChanged: started ? _setVisible : null,
                ),
                SwitchListTile(
                  title: Text(context.loc.settings.backupAndTransfer.includeDeviceSpecificSettings),
                  subtitle: Text(
                    context.loc.settings.backupAndTransfer.includeDeviceSpecificSettingsSubtitle,
                  ),
                  value: includeDeviceSpecificSettings,
                  onChanged: _hasActiveTransfer ? null : _setIncludeDeviceSpecificSettings,
                  secondary: IconButton(
                    icon: const Icon(Icons.help_outline),
                    tooltip: context.loc.settings.backupAndTransfer.includeDeviceSpecificSettingsHelpTitle,
                    onPressed: _showDeviceSpecificSettingsHelp,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _InfoRow(
                    label: context.loc.settings.backupAndTransfer.address,
                    value: address ?? context.loc.settings.backupAndTransfer.starting,
                    onTap: address == null ? null : () => _copyAddress(address),
                    trailing: address == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.copy),
                            tooltip: context.loc.copy,
                            onPressed: () => _copyAddress(address),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _InfoRow(
                    label: context.loc.settings.backupAndTransfer.name,
                    value: deviceName.isEmpty ? context.loc.settings.backupAndTransfer.starting : deviceName,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: _InfoRow(
                    label: context.loc.settings.backupAndTransfer.status,
                    value: started
                        ? (visible
                              ? context.loc.settings.backupAndTransfer.broadcasting
                              : context.loc.settings.backupAndTransfer.hidden)
                        : (starting
                              ? context.loc.settings.backupAndTransfer.starting
                              : context.loc.settings.backupAndTransfer.serverStopped),
                  ),
                ),
                if (!started)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: starting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.play_circle_outline),
                        label: Text(context.loc.settings.backupAndTransfer.send),
                        onPressed: starting ? null : _start,
                      ),
                    ),
                  ),
              ],
            ),
            if (_hasActiveTransfer)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    _InfoRow(
                      label: context.loc.settings.backupAndTransfer.transferred,
                      value: _formatProgress(stats),
                    ),
                    if (stats?.totalBytes != null)
                      _InfoRow(
                        label: context.loc.settings.backupAndTransfer.total,
                        value: TransferFormatters.bytes(stats?.totalBytes ?? 0),
                      ),
                    _InfoRow(
                      label: context.loc.settings.backupAndTransfer.elapsed,
                      value: TransferFormatters.duration(DateTime.now().difference(stats?.startedAt ?? DateTime.now())),
                    ),
                    _InfoRow(
                      label: context.loc.settings.backupAndTransfer.speed,
                      value: '${TransferFormatters.bytes(stats?.bytesPerSecond.round() ?? 0)}/s',
                    ),
                    _InfoRow(
                      label: context.loc.settings.backupAndTransfer.current,
                      value: stats?.currentEntry ?? '-',
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: Text(context.loc.media.loading.stopLoading),
                          onPressed: _cancelTransfer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(context.loc.settings.backupAndTransfer.logs, style: Theme.of(context).textTheme.titleLarge),
            ),
            for (final indexedLog in logs.take(100).indexed)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ListTile(
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
              ),
            _HistorySection(history: history),
          ],
        ),
      ),
    );
  }

  Future<void> _copyAddress(String address) async {
    await Clipboard.setData(ClipboardData(text: address));
    if (!mounted) return;
    FlashElements.showSnackbar(
      context: context,
      title: Text(context.loc.copied),
      content: Text(context.loc.copiedToClipboard),
      leadingIcon: Icons.copy,
      leadingIconColor: Colors.green,
      sideColor: Colors.green,
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
    if (index != 0 || !started) return false;
    return stats?.isComplete != true;
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
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(t.history, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ListTile(title: Text(t.noHistory)),
          )
        else
          for (final entry in history.take(20))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(label),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(value, textAlign: TextAlign.end, overflow: TextOverflow.ellipsis),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

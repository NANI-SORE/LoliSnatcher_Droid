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
import 'package:lolisnatcher/src/pages/settings/backup_transfer_widgets.dart';
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
  late final server = TransferSocketServer(approveRequest: _approveTransfer);
  final discovery = TransferDiscoveryService();
  final historyService = const TransferHistoryService();
  final scrollController = ScrollController();
  final logs = <BackupTransferLog>[];
  List<TransferHistoryEntry> history = [];
  BackupTransferStats? stats;
  String? transferError;
  StreamSubscription<BackupTransferLog>? logSub;
  StreamSubscription<BackupTransferStats>? statsSub;
  bool includeDeviceSpecificSettings = false;
  bool started = false;
  bool starting = false;
  String ip = '';
  String deviceName = '';
  String deviceId = '';
  bool keepAwake = false;
  int _startGeneration = 0;

  Future<bool> _approveTransfer(TransferRequest request) async {
    if (!mounted || !started) return false;
    final navigator = Navigator.of(context);
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => BackupSelectionDialog(
        icon: const Icon(Icons.devices),
        title: Text(dialogContext.loc.settings.backupAndTransfer.approveTransferTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              dialogContext.loc.settings.backupAndTransfer.approveTransferRequest(
                device: request.deviceName,
                address: request.address,
              ),
            ),
            const SizedBox(height: 16),
            BackupEntryTree(
              entryIds: {
                ...request.entries,
                if (request.entries.contains(BackupEntryId.database)) ...BackupEntryRegistry.databaseChildIds,
              },
              entryBuilder: (entry) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(entry.icon),
                title: Text(entry.title()),
                subtitle: Text(entry.description()),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => navigator.pop(false), child: Text(dialogContext.loc.cancel)),
          FilledButton(
            onPressed: () => navigator.pop(true),
            child: Text(dialogContext.loc.settings.backupAndTransfer.allowTransfer),
          ),
        ],
      ),
    );
    unawaited(
      request.cancelled.then((_) {
        if (route.isActive) navigator.removeRoute(route, false);
      }),
    );
    return await navigator.push(route) ?? false;
  }

  bool get _hasActiveTransfer => server.isTransferring.value;

  bool get visible => SX.syncVisibleOnNetwork.state.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    SX.syncVisibleOnNetwork.state.effectiveNotifier.addListener(_onVisibleChanged);
    server.isTransferring.addListener(_onTransferActivityChanged);

    logSub = server.logs.stream.listen((log) {
      if (!mounted) return;
      setState(() => logs.insert(0, log));
    });
    statsSub = server.stats.stream.listen((newStats) {
      if (!mounted) return;
      final transferStarting = !newStats.isComplete && stats?.startedAt != newStats.startedAt;
      setState(() {
        stats = newStats;
        transferError = newStats.currentEntry == 'error' ? logs.firstOrNull?.message : null;
      });
      if (transferStarting) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !scrollController.hasClients) return;
          unawaited(scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut));
        });
      }
      if (newStats.isComplete) unawaited(_loadHistory());
    });
    unawaited(_start());
    unawaited(_loadHistory());
  }

  void _onTransferActivityChanged() {
    if (mounted) setState(() {});
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
    if (!mounted || started || starting) return;
    final generation = ++_startGeneration;
    if (mounted) {
      setState(() {
        starting = true;
        stats = null;
        transferError = null;
      });
    } else {
      starting = true;
      stats = null;
    }
    try {
      ip = await ServiceHandler.getIP();
      deviceName = await TransferDeviceInfo.displayName();
      deviceId = await TransferDeviceInfo.instanceId();
      if (!mounted || generation != _startGeneration) return;
      await server.start(deviceName: deviceName);
      if (!mounted || generation != _startGeneration || server.port == null) return;
      _setKeepAwake(true);
      started = true;
      if (visible) {
        await discovery.startBroadcast(deviceName: deviceName, deviceId: deviceId, port: server.port!);
      }
    } catch (error) {
      await server.stop();
      _setKeepAwake(false);
      started = false;
      if (mounted) {
        setState(
          () => logs.insert(
            0,
            BackupTransferLog(context.loc.settings.backupAndTransfer.transferStartFailed(error: error.toString())),
          ),
        );
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
    ++_startGeneration;
    await discovery.stopBroadcast();
    await server.stop();
    _setKeepAwake(false);
    if (!mounted) return;
    setState(() {
      started = false;
      starting = false;
    });
  }

  void _clearTransferError() {
    if (_hasActiveTransfer || stats?.isComplete != true || stats?.currentEntry != 'error') return;
    setState(() {
      stats = null;
      transferError = null;
    });
  }

  Future<void> _cancelTransfer() async {
    await server.cancelTransfers();
    if (!mounted) return;
    setState(() {
      stats = null;
      transferError = null;
    });
  }

  @override
  void dispose() {
    ++_startGeneration;
    WidgetsBinding.instance.removeObserver(this);
    SX.syncVisibleOnNetwork.state.effectiveNotifier.removeListener(_onVisibleChanged);
    server.isTransferring.removeListener(_onTransferActivityChanged);
    _setKeepAwake(false);
    logSub?.cancel();
    statsSub?.cancel();
    scrollController.dispose();
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
    final t = context.loc.settings.backupAndTransfer;
    final port = server.port;
    final address = port == null || ip.isEmpty ? null : '$ip:$port';
    final status = started
        ? (visible ? t.broadcasting : t.hidden)
        : starting
        ? t.starting
        : t.serverStopped;
    return PopScope(
      canPop: !_hasActiveTransfer,
      child: Scaffold(
        appBar: SettingsAppBar(
          title: t.sendDataTitle,
          leading: _hasActiveTransfer ? const IconButton(onPressed: null, icon: BackButtonIcon()) : null,
        ),
        body: BackupPageBody(
          controller: scrollController,
          children: [
            if (stats != null)
              BackupTransferProgress(
                stats: stats,
                isReceiving: false,
                errorMessage: transferError,
                onClearError: _hasActiveTransfer ? null : _clearTransferError,
                onCancel: _hasActiveTransfer ? _cancelTransfer : null,
              ),
            BackupNotice(message: t.sendInstructions, icon: Icons.devices),
            const SizedBox(height: 24),
            BackupSection(
              title: t.deviceInfo,
              children: [
                ListTile(
                  leading: starting
                      ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(started ? Icons.wifi : Icons.wifi_off),
                  title: Text(deviceName.isEmpty ? t.sendDataTitle : deviceName),
                  subtitle: Semantics(liveRegion: true, child: Text(status)),
                ),
                if (address != null)
                  ListTile(
                    leading: const Icon(Icons.link),
                    title: Text(t.address),
                    subtitle: SelectableText(address),
                    trailing: IconButton(
                      tooltip: context.loc.copy,
                      icon: const Icon(Icons.copy),
                      onPressed: () => _copyAddress(address),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: started
                      ? OutlinedButton.icon(
                          onPressed: _hasActiveTransfer ? null : _stop,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: Text(t.stopSharing),
                        )
                      : FilledButton.icon(
                          onPressed: starting ? null : _start,
                          icon: const Icon(Icons.play_circle_outline),
                          label: Text(t.send),
                        ),
                ),
              ],
            ),
            BackupSection(
              title: t.transferData,
              children: [
                SwitchListTile(
                  title: Text(t.visibleOnNetwork),
                  subtitle: Text(t.visibleOnNetworkSubtitle),
                  value: visible,
                  onChanged: starting ? null : _setVisible,
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(t.includeDeviceSpecificSettings),
                  subtitle: Text(t.includeDeviceSpecificSettingsSubtitle),
                  value: includeDeviceSpecificSettings,
                  onChanged: _hasActiveTransfer ? null : _setIncludeDeviceSpecificSettings,
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: TextButton.icon(
                      icon: const Icon(Icons.help_outline),
                      label: Text(t.includeDeviceSpecificSettingsHelpTitle),
                      onPressed: _showDeviceSpecificSettingsHelp,
                    ),
                  ),
                ),
              ],
            ),
            BackupTransferActivity(logs: logs, history: history),
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
}

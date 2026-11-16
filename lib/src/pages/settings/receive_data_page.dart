import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lolisnatcher/src/handlers/settings_handler.dart';
import 'package:lolisnatcher/src/data/settings/setting_key.dart';
import 'package:lolisnatcher/src/pages/settings/backup_feedback.dart';
import 'package:lolisnatcher/src/pages/settings/backup_theme.dart';
import 'package:lolisnatcher/src/handlers/service_handler.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_entry_registry.dart';
import 'package:lolisnatcher/src/services/backup_transfer/backup_models.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_device_info.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_discovery_service.dart';
import 'package:lolisnatcher/src/pages/settings/backup_transfer_widgets.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_history_service.dart';
import 'package:lolisnatcher/src/services/backup_transfer/transfer_socket_client.dart';
import 'package:lolisnatcher/src/services/local_network_permission.dart';
import 'package:lolisnatcher/src/pages/settings/transfer_verification_notice.dart';
import 'package:lolisnatcher/src/widgets/common/settings_widgets.dart';

class ReceiveDataPage extends StatefulWidget {
  const ReceiveDataPage({super.key});

  @override
  State<ReceiveDataPage> createState() => _ReceiveDataPageState();
}

class _ReceiveDataPageState extends State<ReceiveDataPage> with WidgetsBindingObserver {
  final discovery = TransferDiscoveryService();
  final client = TransferSocketClient();
  final historyService = const TransferHistoryService();
  final scrollController = ScrollController();
  final logs = <BackupTransferLog>[];
  List<DiscoveredTransferDevice> devices = [];
  List<TransferHistoryEntry> history = [];
  BackupTransferStats? stats;
  StreamSubscription<List<DiscoveredTransferDevice>>? devicesSub;
  StreamSubscription<Object?>? discoveryErrorSub;
  StreamSubscription<BackupTransferLog>? logSub;
  StreamSubscription<BackupTransferStats>? statsSub;
  bool receiving = false;
  String? verificationPhrase;
  bool keepAwake = false;
  String ip = '';
  String deviceName = '';
  String deviceId = '';
  bool discovering = true;
  Object? discoveryError;
  Timer? discoveryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    discoveryErrorSub = discovery.errors.listen((error) {
      if (!mounted) return;
      setState(() {
        discoveryError = error;
        if (error != null) discovering = false;
      });
    });
    devicesSub = discovery.devices.listen((newDevices) {
      if (!mounted) return;
      setState(
        () => devices = [
          ...devices.where((device) => device.isManual),
          ...newDevices.where(
            (device) => !devices.any((manual) => manual.isManual && manual.address == device.address),
          ),
        ],
      );
    });
    logSub = client.logs.stream.listen((log) {
      if (!mounted) return;
      setState(() => logs.insert(0, log));
    });
    statsSub = client.stats.stream.listen((newStats) {
      if (!mounted) return;
      setState(() => stats = newStats);
    });
    unawaited(
      _loadDeviceInfoAndStartDiscovery(retryPermission: true).catchError((Object error) {
        if (mounted) setState(() => logs.insert(0, BackupTransferLog(error.toString())));
      }),
    );
    unawaited(_loadHistory());
  }

  Future<void> _loadDeviceInfoAndStartDiscovery({bool retryPermission = false}) async {
    if (!mounted) return;
    setState(() {
      discovering = true;
      discoveryError = null;
    });
    discoveryTimer?.cancel();
    try {
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
        retryPermission: retryPermission,
      );
      if (!mounted) return;
      discoveryTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => discovering = false);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          discovering = false;
          discoveryError = error;
        });
      }
    }
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
    discoveryTimer?.cancel();
    devicesSub?.cancel();
    discoveryErrorSub?.cancel();
    logSub?.cancel();
    statsSub?.cancel();
    scrollController.dispose();
    unawaited(discovery.dispose());
    unawaited(client.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (keepAwake) ServiceHandler.disableSleep(force: true);
      unawaited(
        _loadDeviceInfoAndStartDiscovery().catchError((Object error) {
          if (mounted) setState(() => logs.insert(0, BackupTransferLog(error.toString())));
        }),
      );
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
    final address = await showDialog<String>(
      context: context,
      builder: (_) => const _ManualDeviceDialog(),
    );
    if (!mounted || address == null) return;
    final parts = address.split(':');
    setState(() {
      devices = [
        ...devices.where((device) => device.address != address),
        DiscoveredTransferDevice(
          id: address,
          name: context.loc.settings.backupAndTransfer.manualDevice,
          host: parts.first,
          port: int.parse(parts.last),
          version: context.loc.settings.backupAndTransfer.unknown,
          build: null,
          deviceId: null,
          isManual: true,
        ),
      ];
    });
  }

  Future<void> _selectAndReceive(DiscoveredTransferDevice device) async {
    if (receiving) return;
    setState(() {
      stats = null;
      verificationPhrase = null;
      receiving = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      unawaited(scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut));
    });
    _setKeepAwake(true);
    try {
      await client.receive(
        host: device.host,
        port: device.port,
        receiverName: deviceName,
        senderName: device.name,
        senderAddress: device.address,
        onVerificationPhrase: (phrase) {
          if (mounted) setState(() => verificationPhrase = phrase);
        },
        selectEntries: (available, disconnected) async {
          if (!mounted) return null;
          final navigator = Navigator.of(context);
          final route = DialogRoute<_ReceiveSelection>(
            context: context,
            builder: (_) => _ReceiveSelectionDialog(device: device, available: available.toSet()),
          );
          unawaited(
            disconnected.then((_) {
              if (route.isActive) navigator.removeRoute(route);
            }),
          );
          final selection = await navigator.push(route);
          if (selection == null) return null;
          return TransferReceiveSelection(
            entries: selection.entries,
            transferOptions: {
              'favouritesStartIndex': selection.favouritesStartIndex,
              'snatchedStartIndex': selection.snatchedStartIndex,
            },
            importOptions: BackupImportOptions(tabsMode: selection.tabsMode, tagsMode: selection.tagsMode),
          );
        },
      );
    } catch (error) {
      if (mounted) setState(() => logs.insert(0, BackupTransferLog(error.toString())));
    } finally {
      _setKeepAwake(false);
      unawaited(_loadHistory());
      if (mounted) {
        setState(() {
          receiving = false;
          verificationPhrase = null;
        });
        unawaited(discovery.refreshDiscovery());
      }
    }
  }

  void _clearTransfer() {
    if (!receiving) setState(() => stats = null);
  }

  Future<void> _cancelReceive() async {
    if (client.importing) return;
    await client.cancel();
    _setKeepAwake(false);
    if (!mounted) return;
    setState(() => receiving = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    return PopScope(
      canPop: !receiving,
      child: Scaffold(
        appBar: SettingsAppBar(
          title: t.receiveDataTitle,
          leading: receiving ? const IconButton(onPressed: null, icon: BackButtonIcon()) : null,
        ),
        body: BackupPageBody(
          controller: scrollController,
          children: [
            if (receiving && verificationPhrase != null) TransferVerificationNotice(phrase: verificationPhrase!),
            if (receiving || stats != null)
              BackupTransferProgress(
                stats: stats,
                isReceiving: true,
                errorMessage: stats?.message,
                onClearError: receiving ? null : _clearTransfer,
                onCancel: receiving && !client.importing ? _cancelReceive : null,
              ),
            BackupNotice(message: t.receiveInstructions, icon: Icons.devices),
            const SizedBox(height: 12),
            BackupNotice(message: t.vpnNotice, icon: Icons.vpn_lock_outlined),
            const SizedBox(height: 24),
            if (discoveryError != null) ...[
              BackupNotice(
                message: discoveryError is LocalNetworkPermissionDenied
                    ? context.loc.permissions.localNetworkRequired
                    : t.discoveryFailed,
                isWarning: true,
              ),
              BackupErrorDetails(details: discoveryError.toString()),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: receiving ? null : () => _loadDeviceInfoAndStartDiscovery(retryPermission: true),
                  child: Text(t.retryDiscovery),
                ),
              ),
            ],
            BackupSection(
              title: t.nearbyDevices,
              trailing: TextButton.icon(
                onPressed: receiving ? null : _addManual,
                icon: const Icon(Icons.add),
                label: Text(t.addDevice),
              ),
              children: [
                if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        if (discovering) ...[const CircularProgressIndicator(), const SizedBox(height: 16)],
                        Icon(Icons.devices_other, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(
                          discovering ? t.lookingForDevices : t.noDevicesFound,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(t.noDevicesHint, textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                for (final device in devices)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: const Icon(Icons.devices),
                    title: Text(device.name),
                    subtitle: Text(
                      '${device.address}\n${device.version}${device.build != null ? ' (${device.build})' : ''}${device.isManual ? ' · ${t.manual}' : ''}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    enabled: !receiving,
                    onTap: receiving ? null : () => _selectAndReceive(device),
                  ),
              ],
            ),
            BackupSection(
              title: t.deviceInfo,
              children: [
                ListTile(
                  leading: const Icon(Icons.smartphone),
                  title: Text(deviceName.isEmpty ? t.starting : deviceName),
                  subtitle: SelectableText(ip.isEmpty ? (deviceName.isEmpty ? t.starting : t.noLocalAddress) : ip),
                ),
              ],
            ),
            BackupTransferActivity(logs: logs, history: history),
          ],
        ),
      ),
    );
  }
}

class _ReceiveSelection {
  const _ReceiveSelection({
    required this.entries,
    required this.tabsMode,
    required this.tagsMode,
    required this.favouritesStartIndex,
    required this.snatchedStartIndex,
  });

  final List<BackupEntryId> entries;
  final BackupTabsMode tabsMode;
  final BackupTagsMode tagsMode;
  final int favouritesStartIndex;
  final int snatchedStartIndex;
}

class _ReceiveSelectionDialog extends StatefulWidget {
  const _ReceiveSelectionDialog({required this.device, required this.available});
  final Set<BackupEntryId> available;

  final DiscoveredTransferDevice device;

  @override
  State<_ReceiveSelectionDialog> createState() => _ReceiveSelectionDialogState();
}

class _ReceiveSelectionDialogState extends State<_ReceiveSelectionDialog> {
  final registry = BackupEntryRegistry.instance;
  final selected = <BackupEntryId>{};
  BackupTabsMode tabsMode = BackupTabsMode.merge;
  BackupTagsMode tagsMode = BackupTagsMode.preferTypeIfNone;
  final favouritesStartController = TextEditingController(text: '0');
  final snatchedStartController = TextEditingController(text: '0');
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    // showDialog returns before the closing animation finishes. Keep these
    // alive until the dialog and its text fields are actually unmounted.
    favouritesStartController.dispose();
    snatchedStartController.dispose();
    super.dispose();
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

    if (registry.isDatabaseChild(entryId) && selected.contains(BackupEntryRegistry.databaseParentId)) return;

    if (value) {
      selected.add(entryId);
    } else {
      selected.remove(entryId);
    }
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

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    return BackupSelectionDialog(
      icon: const Icon(Icons.download_rounded),
      title: Text(t.selectedData),
      warning: selected.contains(BackupEntryId.database)
          ? BackupNotice(message: t.databaseReplacementWarning, isWarning: true)
          : null,
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.device.name, style: Theme.of(context).textTheme.titleMedium),
            Text(widget.device.address, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Text(t.selectedImportOnly),
            const SizedBox(height: 12),
            BackupEntryTree(
              entryIds: registry.defaultEntries.map((entry) => entry.id),
              entryOptionsBuilder: (entry) {
                if (!selected.contains(entry.id)) return null;
                return switch (entry.id) {
                  BackupEntryId.tabs || BackupEntryId.tags => BackupRestoreOptions(
                    showTabs: entry.id == BackupEntryId.tabs,
                    showTags: entry.id == BackupEntryId.tags,
                    tabsMode: tabsMode,
                    tagsMode: tagsMode,
                    onTabsModeChanged: (value) => setState(() => tabsMode = value),
                    onTagsModeChanged: (value) => setState(() => tagsMode = value),
                  ),
                  BackupEntryId.favourites => ExpansionTile(
                    title: Text(t.advancedOptions),
                    children: [_StartIndexField(controller: favouritesStartController, label: t.favouritesStartIndex)],
                  ),
                  BackupEntryId.snatched => ExpansionTile(
                    title: Text(t.advancedOptions),
                    children: [_StartIndexField(controller: snatchedStartController, label: t.snatchedStartIndex)],
                  ),
                  _ => null,
                };
              },
              entryBuilder: (entry) {
                // Only an explicit full-database selection locks child categories.
                final includedInDatabase =
                    registry.isDatabaseChild(entry.id) && selected.contains(BackupEntryId.database);
                final unavailable = !widget.available.contains(entry.id);
                final needsDatabase =
                    registry.requiresDatabase(entry.id) &&
                    !SX.dbEnabled.value &&
                    !selected.contains(BackupEntryId.database);
                return BackupEntryCheckbox(
                  entry: entry,
                  selected: includedInDatabase || selected.contains(entry.id),
                  disabledReason: includedInDatabase
                      ? null
                      : unavailable
                      ? t.unavailableOnSender
                      : needsDatabase
                      ? t.enableDatabaseFirst
                      : null,
                  onChanged: includedInDatabase || unavailable || needsDatabase
                      ? null
                      : (value) => setState(() => _setTreeEntrySelected(selected, entry.id, value)),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.loc.cancel)),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded),
          onPressed: selected.isEmpty
              ? null
              : () {
                  if (!formKey.currentState!.validate()) return;
                  Navigator.pop(
                    context,
                    _ReceiveSelection(
                      entries: _normalizedSelectedEntries(selected),
                      tabsMode: tabsMode,
                      tagsMode: tagsMode,
                      favouritesStartIndex: int.tryParse(favouritesStartController.text) ?? 0,
                      snatchedStartIndex: int.tryParse(snatchedStartController.text) ?? 0,
                    ),
                  );
                },
          label: Text(t.receive),
        ),
      ],
    );
  }
}

class _StartIndexField extends StatelessWidget {
  const _StartIndexField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        helperText: context.loc.settings.backupAndTransfer.startIndexHint,
        helperMaxLines: 3,
        errorMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (value) {
        final index = int.tryParse(value ?? '');
        return index == null || index < 0 || index > 0x7fffffff
            ? context.loc.settings.backupAndTransfer.invalidStartIndex
            : null;
      },
    ),
  );
}

class _ManualDeviceDialog extends StatefulWidget {
  const _ManualDeviceDialog();
  @override
  State<_ManualDeviceDialog> createState() => _ManualDeviceDialogState();
}

class _ManualDeviceDialogState extends State<_ManualDeviceDialog> {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    if (formKey.currentState!.validate()) Navigator.pop(context, controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.loc.settings.backupAndTransfer;
    return BackupControlsTheme(
      child: AlertDialog(
        icon: const Icon(Icons.add_link),
        title: Text(t.addDevice),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: t.address,
                hintText: '192.168.1.10:12345',
                helperText: t.manualAddressHint,
                helperMaxLines: 4,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final parts = (value ?? '').trim().split(':');
                final octets = parts.first.split('.');
                final port = parts.length == 2 ? int.tryParse(parts.last) : null;
                if (octets.length != 4 ||
                    octets.any((part) => !RegExp(r'^\d{1,3}$').hasMatch(part) || int.parse(part) > 255) ||
                    port == null ||
                    port < 1 ||
                    port > 65535) {
                  return t.invalidDeviceAddress;
                }
                return null;
              },
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.loc.cancel)),
          FilledButton(onPressed: submit, child: Text(context.loc.add)),
        ],
      ),
    );
  }
}

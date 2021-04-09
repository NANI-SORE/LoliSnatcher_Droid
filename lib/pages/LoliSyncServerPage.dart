import 'package:LoliSnatcher/SettingsHandler.dart';
import 'package:LoliSnatcher/libBooru/BooruItem.dart';
import 'package:LoliSnatcher/libBooru/LoliSync.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:core';
import 'package:get/get.dart';

import '../ServiceHandler.dart';

class LoliSyncServerPage extends StatefulWidget {
  SettingsHandler settingsHandler;
  LoliSyncServerPage(this.settingsHandler);
  @override
  _LoliSyncServerPageState createState() => _LoliSyncServerPageState();
}

class _LoliSyncServerPageState extends State<LoliSyncServerPage> {
  LoliSync loliSync = new LoliSync();
  @override
  // These lines are done in init state as they only need to be run once when the widget is first loaded
  void initState() {
    super.initState();
  }
  Future<bool> _onWillPop() async {
    return true;
  }
  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          title: Text("Loli Sync"),
          leading: new IconButton(
              icon: new Icon(Icons.arrow_back),
              onPressed: () async{
                Get.back();
              }
          ),
        ),
        body:Center(
            child: StreamBuilder<String>(
              stream: loliSync.startServer(widget.settingsHandler),
              builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
                String status = "";
                if (snapshot.hasError) {
                  status = "Error";
                } else {
                  switch (snapshot.connectionState) {
                    case ConnectionState.none:
                    case ConnectionState.waiting:
                      status = "No connection";
                      break;
                    case ConnectionState.active:
                    case ConnectionState.done:
                      status = "${snapshot.data}";
                      break;
                  }
                }
                return Center(
                  child: Column(
                    children: [
                      Icon(Icons.electrical_services, size: 400),
                      Text(status),
                    ],
                  ),
                );
              },
            )
        ),
      ),
    );
  }
}


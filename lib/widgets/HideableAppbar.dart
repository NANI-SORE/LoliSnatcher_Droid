import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import 'package:LoliSnatcher/SearchGlobals.dart';
// import 'package:LoliSnatcher/ServiceHandler.dart';

class HideableAppBar extends StatefulWidget implements PreferredSizeWidget {
  String title;
  List<Widget> actions;
  SearchGlobals searchGlobals;
  bool autoHide;
  HideableAppBar(this.title, this.actions, this.searchGlobals, this.autoHide);

  final double defaultHeight = kToolbarHeight; //56.0
  @override
  Size get preferredSize => Size.fromHeight(defaultHeight);
  @override
  _HideableAppBarState createState() => _HideableAppBarState();
}

class _HideableAppBarState extends State<HideableAppBar> {
  @override
  void initState() {
    super.initState();
    widget.searchGlobals.displayAppbar.value = !widget.autoHide;
    widget.searchGlobals.displayAppbar.addListener(setSt);

    // Hide system ui on first render
    // SystemChrome.setEnabledSystemUIOverlays([SystemUiOverlay.bottom]);
    // ServiceHandler.makeImmersive();
  }
  void setSt(){
    setState(() {});
  }
  @override
  void dispose() {
    widget.searchGlobals.displayAppbar.removeListener(setSt);

    // Return system ui after closing viewer
    // ServiceHandler.makeNormal();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    //Hide status bar and bottom navbar
    // Bug: triggers restate => forces video restart, animation lags
    // !widget.searchGlobals.displayAppbar.value ? SystemChrome.setEnabledSystemUIOverlays([]) : SystemChrome.setEnabledSystemUIOverlays(SystemUiOverlay.values);

    return SafeArea( // to fix height bug when bar on top
      child: AnimatedContainer(
        duration: Duration(milliseconds: 200),
        curve: Curves.linear,
        color: Colors.transparent,
        height: widget.searchGlobals.displayAppbar.value ? widget.defaultHeight : 0.0,
        child: AppBar(
          // toolbarHeight: widget.defaultHeight,
          // elevation: 0, // set to zero to disable a shadow behind
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          leading: IconButton(
            // to ignore icon change
            icon: Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: FittedBox(
            fit: BoxFit.fitWidth,
            child: Text(widget.title, style: TextStyle(color: Colors.white)),
          ),
          actions: widget.actions,
        ),
      )
    );
  }
}

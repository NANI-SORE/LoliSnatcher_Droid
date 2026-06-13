import 'dart:io';

import 'package:flutter/material.dart';

import 'package:lolisnatcher/src/data/settings/setting_key.dart';

class MascotImage extends StatelessWidget {
  const MascotImage({super.key});

  @override
  Widget build(BuildContext context) {
    final String mascotPath = SX.drawerMascotPathOverride.value;

    return Align(
      alignment: FractionalOffset.bottomCenter,
      child: Image(
        fit: BoxFit.contain,
        image: mascotPath.isEmpty
            ? const AssetImage('assets/images/drawer_icon.png')
            : FileImage(File(mascotPath)) as ImageProvider,
      ),
    );
  }
}

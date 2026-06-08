import 'package:flutter/material.dart';

import 'package:lolisnatcher/gen/strings.g.dart';

class DeleteButton extends StatelessWidget {
  const DeleteButton({
    this.action,
    this.returnData,
    this.withIcon = false,
    this.text,
    this.enabled = true,
    super.key,
  });

  final VoidCallback? action;
  final dynamic returnData;
  final bool withIcon;
  final String? text;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (withIcon) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          foregroundColor: Colors.white,
          iconColor: Colors.white,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: enabled
            ? () {
                if (action != null) {
                  action?.call();
                } else {
                  Navigator.of(context).pop(returnData);
                }
              }
            : null,
        icon: const Icon(Icons.delete_forever),
        label: Text(text ?? context.loc.delete),
      );
    }

    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      onPressed: () {
        if (action != null) {
          action?.call();
        } else {
          Navigator.of(context).pop(returnData);
        }
      },
      child: Text(text ?? context.loc.delete),
    );
  }
}

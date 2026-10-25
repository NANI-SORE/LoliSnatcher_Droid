// Protocol symbols stay identical across app languages. Preserve this order.
const _emojis = <String>[
  '😭',
  '🐶',
  '🐱',
  '🦁',
  '🐴',
  '🦄',
  '🐷',
  '🐘',
  '🐰',
  '🐼',
  '🐓',
  '🐧',
  '🐢',
  '🐟',
  '🐙',
  '🦋',
  '🌷',
  '🌳',
  '🌵',
  '🍄',
  '🌏',
  '🌙',
  '☁️',
  '🔥',
  '🍌',
  '🍎',
  '🍓',
  '🌽',
  '🍕',
  '🎂',
  '❤️',
  '😀',
  '🤖',
  '🎩',
  '👓',
  '🔧',
  '🎅',
  '👍',
  '☂️',
  '⌛',
  '⏰',
  '🎁',
  '💡',
  '📕',
  '✏️',
  '📎',
  '✂️',
  '🔒',
  '🔑',
  '🔨',
  '☎️',
  '🏁',
  '🚂',
  '🚲',
  '✈️',
  '🚀',
  '🏆',
  '⚽',
  '🎸',
  '🎺',
  '🔔',
  '⚓',
  '🎧',
  '📁',
];

final _validEmojiTable = _emojis.length == 64 && _emojis.toSet().length == 64;

String transferVerificationPhrase(List<int> bytes) {
  if (!_validEmojiTable) throw StateError('Transfer verification requires exactly 64 distinct emojis');
  if (bytes.length != 6 || bytes.any((value) => value < 0 || value > 255)) {
    throw const FormatException('Invalid transfer verification value');
  }
  // Six independent 6-bit symbols preserve 36 verification bits. Every symbol
  // has exactly four byte preimages, so masking introduces no selection bias.
  return bytes.map((value) => _emojis[value & 63]).join(' ');
}

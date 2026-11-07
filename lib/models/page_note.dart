import '../ink/ink_core.dart';

enum NotePaperStyle { blank, grid, lined, dotted }

class PageNote {
  final String id;
  final String text;
  final String fontFamily;
  final double fontSize;
  final NotePaperStyle paperStyle;
  final List<InkStroke> strokes;

  const PageNote({
    required this.id,
    required this.text,
    required this.fontFamily,
    required this.fontSize,
    this.paperStyle = NotePaperStyle.blank,
    this.strokes = const [],
  });

  PageNote copyWith({
    String? text,
    String? fontFamily,
    double? fontSize,
    NotePaperStyle? paperStyle,
    List<InkStroke>? strokes,
  }) =>
      PageNote(
        id: id,
        text: text ?? this.text,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        paperStyle: paperStyle ?? this.paperStyle,
        strokes: strokes ?? this.strokes,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'text': text,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'paperStyle': paperStyle.name,
        'strokes': [for (final stroke in strokes) stroke.toJson()],
      };

  factory PageNote.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final text = json['text'];
    final fontFamily = json['fontFamily'];
    final fontSize = json['fontSize'];
    final paperStyle = json['paperStyle'] ?? NotePaperStyle.blank.name;
    final strokes = json['strokes'] ?? const [];
    if (id is! String ||
        text is! String ||
        fontFamily is! String ||
        fontSize is! num ||
        paperStyle is! String ||
        strokes is! List) {
      throw const FormatException('Not sayfası verisi geçersiz.');
    }
    NotePaperStyle? parsedPaperStyle;
    for (final style in NotePaperStyle.values) {
      if (style.name == paperStyle) {
        parsedPaperStyle = style;
        break;
      }
    }
    if (parsedPaperStyle == null) {
      throw const FormatException('Not sayfası kağıt biçimi geçersiz.');
    }
    return PageNote(
      id: id,
      text: text,
      fontFamily: fontFamily,
      fontSize: fontSize.toDouble(),
      paperStyle: parsedPaperStyle,
      strokes: [
        for (final stroke in strokes)
          InkStroke.fromJson(stroke as Map<String, dynamic>),
      ],
    );
  }
}

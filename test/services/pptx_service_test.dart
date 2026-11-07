import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:baylock/models/pptx_presentation.dart';
import 'package:baylock/services/pptx_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads slide shapes and text under p:cSld/p:spTree', () async {
    final archive = Archive()
      ..addFile(
        _xmlFile('ppt/presentation.xml', '''
<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
 xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <p:sldIdLst><p:sldId id="1" r:id="rId1"/></p:sldIdLst>
  <p:sldSz cx="9144000" cy="5143500"/>
</p:presentation>
'''),
      )
      ..addFile(
        _xmlFile('ppt/_rels/presentation.xml.rels', '''
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="slide" Target="slides/slide1.xml"/>
</Relationships>
'''),
      )
      ..addFile(
        _xmlFile('ppt/slides/slide1.xml', '''
<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"
 xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <p:cSld>
    <p:spTree>
      <p:nvGrpSpPr/><p:grpSpPr/>
      <p:sp>
        <p:spPr>
          <a:xfrm><a:off x="0" y="0"/><a:ext cx="9144000" cy="5143500"/></a:xfrm>
        </p:spPr>
        <p:txBody>
          <a:bodyPr/><a:lstStyle/>
          <a:p><a:r><a:rPr/><a:t>Sunum içeriği</a:t></a:r></a:p>
        </p:txBody>
      </p:sp>
    </p:spTree>
  </p:cSld>
</p:sld>
'''),
      );

    final directory = await Directory.systemTemp.createTemp('pptx-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}\\sample.pptx');
    await file.writeAsBytes(ZipEncoder().encode(archive)!);

    final result = await PptxService.load(file.path);

    expect(result.slides, hasLength(1));
    expect(result.slides.single.elements, hasLength(1));
    final PptxElement element = result.slides.single.elements.single;
    expect(element.paragraphs.single.runs.single.text, 'Sunum içeriği');
  });
}

ArchiveFile _xmlFile(String name, String content) {
  final bytes = utf8.encode(content);
  return ArchiveFile(name, bytes.length, bytes);
}

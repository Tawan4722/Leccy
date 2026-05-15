import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'gemini_service.dart';

class PptxExportService {
  Uint8List buildDeck({
    required String title,
    required List<GeneratedSlide> slides,
  }) {
    final archive = Archive();
    void add(String name, String content) {
      archive.addFile(ArchiveFile.string(name, content));
    }

    add('[Content_Types].xml', _contentTypes(slides.length));
    add('_rels/.rels', _rootRelationships());
    add('ppt/presentation.xml', _presentation(slides.length));
    add(
      'ppt/_rels/presentation.xml.rels',
      _presentationRelationships(slides.length),
    );
    add('docProps/app.xml', _appProperties(slides.length));
    add('docProps/core.xml', _coreProperties(title));
    for (var index = 0; index < slides.length; index++) {
      add('ppt/slides/slide${index + 1}.xml', _slide(slides[index]));
    }

    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  List<GeneratedSlide> slidesFromJson(String slidesJson) {
    final decoded = jsonDecode(slidesJson);
    final slides = decoded is Map ? decoded['slides'] : null;
    if (slides is! List) {
      return const [];
    }
    return slides
        .whereType<Map>()
        .map((item) => GeneratedSlide.fromJson(item.cast<String, Object?>()))
        .toList();
  }

  String slidesToJson(List<GeneratedSlide> slides) {
    return jsonEncode({
      'slides': slides.map((slide) => slide.toJson()).toList(),
    });
  }

  String _contentTypes(int slideCount) {
    final slideOverrides = List.generate(
      slideCount,
      (index) =>
          '<Override PartName="/ppt/slides/slide${index + 1}.xml" '
          'ContentType="application/vnd.openxmlformats-officedocument.'
          'presentationml.slide+xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '$slideOverrides</Types>';
  }

  String _rootRelationships() {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
        '</Relationships>';
  }

  String _presentation(int slideCount) {
    final ids = List.generate(
      slideCount,
      (index) => '<p:sldId id="${256 + index}" r:id="rId${index + 1}"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<p:sldSz cx="12192000" cy="6858000" type="screen16x9"/>'
        '<p:sldIdLst>$ids</p:sldIdLst></p:presentation>';
  }

  String _presentationRelationships(int slideCount) {
    final rels = List.generate(
      slideCount,
      (index) =>
          '<Relationship Id="rId${index + 1}" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
          'Target="slides/slide${index + 1}.xml"/>',
    ).join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">$rels</Relationships>';
  }

  String _slide(GeneratedSlide slide) {
    final body = slide.bullets
        .take(8)
        .map((bullet) => '<a:p><a:r><a:t>${_xml(bullet)}</a:t></a:r></a:p>')
        .join();
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
        'xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main">'
        '<p:cSld><p:spTree>'
        '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr/>'
        '${_textBox(2, 685800, 420000, 10800000, 800000, slide.title, 3600)}'
        '${_bodyBox(body)}'
        '</p:spTree></p:cSld></p:sld>';
  }

  String _textBox(int id, int x, int y, int cx, int cy, String text, int size) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="$id" name="Text $id"/>'
        '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
        '<a:xfrm><a:off x="$x" y="$y"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr sz="$size"/>'
        '<a:t>${_xml(text)}</a:t></a:r></a:p></p:txBody></p:sp>';
  }

  String _bodyBox(String paragraphs) {
    return '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Body"/>'
        '<p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr>'
        '<a:xfrm><a:off x="900000" y="1500000"/><a:ext cx="10300000" cy="4200000"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>'
        '<p:txBody><a:bodyPr/><a:lstStyle/>$paragraphs</p:txBody></p:sp>';
  }

  String _appProperties(int slideCount) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
        '<Application>Leccy</Application><Slides>$slideCount</Slides></Properties>';
  }

  String _coreProperties(String title) {
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>${_xml(title)}</dc:title></cp:coreProperties>';
  }

  String _xml(String value) => XmlText(value).toXmlString();
}

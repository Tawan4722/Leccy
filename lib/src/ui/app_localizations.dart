import 'package:flutter/material.dart';

extension LeccyLocalizationContext on BuildContext {
  String t(String text, [Map<String, Object?> values = const {}]) {
    var translated = Localizations.localeOf(this).languageCode == 'th'
        ? (_thai[text] ?? text)
        : text;
    for (final entry in values.entries) {
      translated = translated.replaceAll('{${entry.key}}', '${entry.value}');
    }
    return translated;
  }

  String filesCount(int count) {
    if (Localizations.localeOf(this).languageCode == 'th') {
      return '$count ไฟล์';
    }
    return count == 1 ? '1 file' : '$count files';
  }

  String slidesCount(int count) {
    if (Localizations.localeOf(this).languageCode == 'th') {
      return '$count สไลด์';
    }
    return count == 1 ? '1 slide' : '$count slides';
  }

  String progressPercent(int percent) {
    return t('Progress {percent}%', {'percent': percent});
  }

  String lastBackup(DateTime dateTime, String formatted) {
    return t('Last backup: {date}', {'date': formatted});
  }

  String backupContents({
    required int folders,
    required int files,
    required int studySets,
  }) {
    return t(
      'This backup contains:\n'
      '- {folders} folders\n'
      '- {files} files\n'
      '- {studySets} study sets\n\n'
      'Replace all: wipe current data and restore from backup.\n'
      'Merge as new: keep current data and append imported folders.',
      {'folders': folders, 'files': files, 'studySets': studySets},
    );
  }
}

const Map<String, String> _thai = {
  'Workspace': 'พื้นที่ทำงาน',
  'Search commands': 'ค้นหาคำสั่ง',
  'Settings': 'การตั้งค่า',
  'New folder': 'โฟลเดอร์ใหม่',
  'Search...': 'ค้นหา...',
  'Sort/View': 'จัดเรียง/มุมมอง',
  'No folders yet': 'ยังไม่มีโฟลเดอร์',
  'Create folder': 'สร้างโฟลเดอร์',
  'Customize folder': 'ปรับแต่งโฟลเดอร์',
  'Create a folder to start': 'สร้างโฟลเดอร์เพื่อเริ่มต้น',
  'Open left panel': 'เปิดแผงซ้าย',
  'Resize left panel': 'ปรับขนาดแผงซ้าย',
  'Resize right panel': 'ปรับขนาดแผงขวา',
  'Open right panel': 'เปิดแผงขวา',
  'Close left panel': 'ปิดแผงซ้าย',
  'Lecture files': 'ไฟล์เลกเชอร์',
  'New file': 'ไฟล์ใหม่',
  'Exit selection mode': 'ออกจากโหมดเลือก',
  'Select lectures': 'เลือกเลกเชอร์',
  'Create progress set': 'สร้างชุดความคืบหน้า',
  'Trash': 'ถังขยะ',
  'No files in this folder': 'ไม่มีไฟล์ในโฟลเดอร์นี้',
  'Create file': 'สร้างไฟล์',
  'No description': 'ไม่มีคำอธิบาย',
  'Marked important': 'ทำเครื่องหมายว่าสำคัญแล้ว',
  'Mark important': 'ทำเครื่องหมายว่าสำคัญ',
  'Move to trash': 'ย้ายไปถังขยะ',
  'Expand section': 'ขยายส่วนนี้',
  'Collapse section': 'ยุบส่วนนี้',
  'Choose or create a lecture file': 'เลือกหรือสร้างไฟล์เลกเชอร์',
  'Untitled lecture': 'เลกเชอร์ไม่มีชื่อ',
  'Exit fullscreen': 'ออกจากเต็มจอ',
  'Fullscreen editor': 'ตัวแก้ไขเต็มจอ',
  'Details': 'รายละเอียด',
  'Description': 'คำอธิบาย',
  'Doing now': 'กำลังทำ',
  'Summarizing': 'กำลังสรุป',
  'Summary': 'สรุป',
  'Auto summary': 'สรุปอัตโนมัติ',
  'Write the lecture note here...': 'เขียนโน้ตเลกเชอร์ที่นี่...',
  'General notes': 'โน้ตทั่วไป',
  'Mind map': 'แผนผังความคิด',
  'Tap a node to jump to that section.': 'แตะโหนดเพื่อไปยังส่วนนั้น',
  'Add branch': 'เพิ่มกิ่ง',
  'New branch': 'กิ่งใหม่',
  'Branch title': 'ชื่อกิ่ง',
  '{count} branches': '{count} กิ่ง',
  'No branches yet': 'ยังไม่มีกิ่ง',
  'Body': 'เนื้อหา',
  'Apply marker': 'ใช้สีไฮไลต์',
  'Clear marker': 'ล้างไฮไลต์',
  'Smaller text': 'ตัวอักษรเล็กลง',
  'Bigger text': 'ตัวอักษรใหญ่ขึ้น',
  'Insert picture': 'แทรกรูปภาพ',
  'Insert video': 'แทรกวิดีโอ',
  'Draw': 'วาด',
  'Insert link': 'แทรกลิงก์',
  'Record voice': 'บันทึกเสียง',
  'Import txt, markdown, json, or leccy':
      'นำเข้า txt, markdown, json หรือ leccy',
  'Export lecture': 'ส่งออกเลกเชอร์',
  'Structuring': 'กำลังจัดโครงสร้าง',
  'Restructure': 'จัดโครงสร้าง',
  'Restore original': 'คืนค่าต้นฉบับ',
  'Hide note accordion': 'ซ่อนแผงหัวข้อ',
  'Show note accordion': 'แสดงแผงหัวข้อ',
  'Hide formatting': 'ซ่อนการจัดรูปแบบ',
  'Show formatting': 'แสดงการจัดรูปแบบ',
  'Search': 'ค้นหา',
  'Previous match': 'ผลลัพธ์ก่อนหน้า',
  'Next match': 'ผลลัพธ์ถัดไป',
  'Marker color': 'สีไฮไลต์',
  'Font size': 'ขนาดตัวอักษร',
  'Small': 'เล็ก',
  'Normal': 'ปกติ',
  'Large': 'ใหญ่',
  'Huge': 'ใหญ่มาก',
  'URL': 'URL',
  'Label': 'ป้ายชื่อ',
  'Cancel': 'ยกเลิก',
  'Insert': 'แทรก',
  'Drawing': 'ภาพวาด',
  'Plain text (.txt)': 'ข้อความธรรมดา (.txt)',
  'Markdown text (.md)': 'ข้อความ Markdown (.md)',
  'Leccy package (.leccy)': 'แพ็กเกจ Leccy (.leccy)',
  'Includes notes, sheet, slides, and flashcards':
      'รวมโน้ต ชีต สไลด์ และแฟลชการ์ด',
  'Record voice note': 'บันทึกโน้ตเสียง',
  'Microphone permission was denied.': 'ไม่ได้รับอนุญาตให้ใช้ไมโครโฟน',
  'No recording was saved.': 'ไม่มีการบันทึกเสียงที่ถูกบันทึกไว้',
  'Recording. Press Insert when finished.': 'กำลังบันทึก กดแทรกเมื่อเสร็จ',
  'Press Record and allow microphone access.': 'กดบันทึกและอนุญาตใช้ไมโครโฟน',
  'Record': 'บันทึก',
  'Saving': 'กำลังบันทึก',
  'Stop': 'หยุด',
  'Play': 'เล่น',
  'Voice recording': 'เสียงบันทึก',
  'Open audio file': 'เปิดไฟล์เสียง',
  'Accordion': 'แผงหัวข้อ',
  'Text block': 'บล็อกข้อความ',
  'Heading': 'หัวข้อ',
  'Sub heading': 'หัวข้อย่อย',
  'Jump to section': 'ไปยังส่วนนี้',
  'No text under this heading yet.': 'ยังไม่มีข้อความใต้หัวข้อนี้',
  'Mini sheet': 'มินิชีต',
  'Add row': 'เพิ่มแถว',
  'Delete row': 'ลบแถว',
  'Graph': 'กราฟ',
  'Generating': 'กำลังสร้าง',
  'Generate with Gemini': 'สร้างด้วย Gemini',
  'Export PPTX': 'ส่งออก PPTX',
  'Generate slides from your note content.': 'สร้างสไลด์จากเนื้อหาโน้ตของคุณ',
  'Slide title': 'ชื่อสไลด์',
  'Bullets, one per line': 'หัวข้อย่อย บรรทัดละหนึ่งรายการ',
  'Flashcards': 'แฟลชการ์ด',
  'Flashcards are locked. Enter API key to enable this tab.':
      'แฟลชการ์ดถูกล็อกอยู่ ใส่ API key เพื่อเปิดใช้แท็บนี้',
  'API key': 'API key',
  'Generate cards': 'สร้างการ์ด',
  'Previous': 'ก่อนหน้า',
  'Next': 'ถัดไป',
  'Generate flashcards from your note content.': 'สร้างแฟลชการ์ดจากเนื้อหาโน้ต',
  'Answer': 'คำตอบ',
  'Question': 'คำถาม',
  'Tap card to flip': 'แตะการ์ดเพื่อพลิก',
  'Tools': 'เครื่องมือ',
  'Close right panel': 'ปิดแผงขวา',
  'Study sets': 'ชุดการเรียน',
  'Select multiple files and press the progress button to link them.':
      'เลือกหลายไฟล์แล้วกดปุ่มความคืบหน้าเพื่อเชื่อมโยง',
  'Open file': 'เปิดไฟล์',
  'Folder progress': 'ความคืบหน้าโฟลเดอร์',
  'Table data': 'ข้อมูลตาราง',
  'Graph from file data': 'กราฟจากข้อมูลไฟล์',
  'Value': 'ค่า',
  'Item': 'รายการ',
  'Total': 'รวม',
  'Avg': 'เฉลี่ย',
  'Max': 'สูงสุด',
  'Min': 'ต่ำสุด',
  'No data yet. Add values in Table mode.':
      'ยังไม่มีข้อมูล เพิ่มค่าในโหมดตาราง',
  'View Options': 'ตัวเลือกมุมมอง',
  'Layout': 'เลย์เอาต์',
  'Sort by': 'จัดเรียงตาม',
  'Custom': 'กำหนดเอง',
  'Name': 'ชื่อ',
  'Progress': 'ความคืบหน้า',
  'Command Palette': 'แผงคำสั่ง',
  'Search notes or run a command': 'ค้นหาโน้ตหรือเรียกใช้คำสั่ง',
  'Create new file': 'สร้างไฟล์ใหม่',
  'Shortcut: Ctrl+N': 'ปุ่มลัด: Ctrl+N',
  'Export backup': 'ส่งออกข้อมูลสำรอง',
  'Import backup': 'นำเข้าข้อมูลสำรอง',
  'Open trash': 'เปิดถังขยะ',
  'No matching notes': 'ไม่พบโน้ตที่ตรงกัน',
  'Trash is empty': 'ถังขยะว่าง',
  'Folder': 'โฟลเดอร์',
  'File': 'ไฟล์',
  'Restore': 'กู้คืน',
  'Delete forever': 'ลบถาวร',
  'Backup exported: {path}': 'ส่งออกข้อมูลสำรองแล้ว: {path}',
  'Backup export failed: {error}': 'ส่งออกข้อมูลสำรองไม่สำเร็จ: {error}',
  'Invalid backup file: {error}': 'ไฟล์ข้อมูลสำรองไม่ถูกต้อง: {error}',
  'Backup imported: {name}': 'นำเข้าข้อมูลสำรองแล้ว: {name}',
  'Backup import failed: {error}': 'นำเข้าข้อมูลสำรองไม่สำเร็จ: {error}',
  'This backup contains:\n'
          '- {folders} folders\n'
          '- {files} files\n'
          '- {studySets} study sets\n\n'
          'Replace all: wipe current data and restore from backup.\n'
          'Merge as new: keep current data and append imported folders.':
      'ข้อมูลสำรองนี้มี:\n'
      '- {folders} โฟลเดอร์\n'
      '- {files} ไฟล์\n'
      '- {studySets} ชุดการเรียน\n\n'
      'แทนที่ทั้งหมด: ล้างข้อมูลปัจจุบันและกู้คืนจากข้อมูลสำรอง\n'
      'รวมเป็นรายการใหม่: เก็บข้อมูลปัจจุบันไว้และเพิ่มโฟลเดอร์ที่นำเข้า',
  'Merge as new': 'รวมเป็นรายการใหม่',
  'Replace all': 'แทนที่ทั้งหมด',
  'Fast mode': 'โหมดเร็ว',
  'Theme': 'ธีม',
  'App font': 'ฟอนต์แอป',
  'Language': 'ภาษา',
  'English': 'English',
  'Thai': 'ไทย',
  'Accent color': 'สีเน้น',
  'Editor paper color': 'สีกระดาษตัวแก้ไข',
  'Saved in this session': 'บันทึกในเซสชันนี้แล้ว',
  'Not set': 'ยังไม่ได้ตั้งค่า',
  'Enter API key': 'ใส่ API key',
  'Backup & restore': 'สำรองและกู้คืน',
  'Export or import a .leccy/.txt backup':
      'ส่งออกหรือนำเข้าข้อมูลสำรอง .leccy/.txt',
  'Last backup: {date}': 'สำรองล่าสุด: {date}',
  'Want more customization? Go here': 'ต้องการปรับแต่งเพิ่มเติม ไปที่นี่',
  'Open': 'เปิด',
  'Hue': 'เฉดสี',
  'Saturation': 'ความอิ่มสี',
  'Brightness': 'ความสว่าง',
  'Progress {percent}%': 'ความคืบหน้า {percent}%',
  'Unsaved': 'ยังไม่บันทึก',
  'Saved': 'บันทึกแล้ว',
  'Folder name': 'ชื่อโฟลเดอร์',
  'Emoji or letters': 'อีโมจิหรือตัวอักษร',
  'Cover image': 'รูปปก',
  'Remove cover image': 'ลบรูปปก',
  'Move To Trash': 'ย้ายไปถังขยะ',
  'Save': 'บันทึก',
};

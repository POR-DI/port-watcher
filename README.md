# Port Watcher

แอปบนแถบเมนู macOS สำหรับดูว่า **โปรแกรมไหนเปิด port อะไรอยู่บนเครื่อง** และปิดโปรแกรมนั้นได้จากที่เดียว

*A macOS menu bar app that shows which process is listening on which port, grouped by process, with one-click kill.*

## ทำไมถึงสร้าง

- เจอ `port already in use` บ่อย ๆ ตอนรัน dev server แล้วต้องมานั่งพิมพ์ `lsof -i :3000` หาว่าใครจับ port อยู่
- `lsof` ตอบเป็นข้อความยาว ๆ อ่านยาก แถม `node` 6 ตัวก็หน้าตาเหมือนกันหมด ไม่รู้ว่าตัวไหนคือโปรเจกต์ไหน
- อยากเข้าใจเรื่อง port / TCP / UDP / process บน macOS ให้ลึกขึ้นผ่านการลงมือทำเอง

โปรเจกต์นี้เป็นเครื่องมือส่วนตัวและโปรเจกต์เรียนรู้ ไม่ได้ตั้งใจส่งขึ้น App Store

## ทำอะไรได้บ้าง

- **แถวละโปรแกรม** — ไอคอนจริงของแอป, ชื่อ, จำนวน port ที่รอรับ (listening) และ connection, **โฟลเดอร์ที่มันรันอยู่** (เช่น `~/Downloads/lab-day-05-start`) เอาเมาส์ชี้ที่ชื่อจะเห็นคำสั่งที่ใช้เปิด (เช่น `node vite --port 5175`)
- **กดขยาย** เห็น port แต่ละอัน พร้อมชื่อ service ที่รู้จัก (`5432 (postgres)`, `5174 (vite)`) และสถานะ (LISTEN / ESTABLISHED …) ชี้ที่สถานะจะมีคำอธิบาย
- **Listening | All** — ค่าเริ่มต้นโชว์เฉพาะ port ที่รอรับ connection (สิ่งที่มักอยากรู้) กด All เพื่อดู connection ขาออกทั้งหมด
- **กรอง TCP / UDP** และ **ค้นหา** ตามชื่อโปรแกรม, port, PID หรือชื่อ service
- **Kill** โปรแกรมจากหัวแถว มีกล่องยืนยันให้เลือก Terminate (ปิดดี ๆ) หรือ Force Kill
- **Settings** — ความถี่ในการสแกน, เปิดตอน login
- สแกนเฉพาะตอนเปิด panel เท่านั้น ปิด panel แล้วแอปแทบไม่ใช้ทรัพยากรเลย
- แอป **ไม่เปิด socket หรือแตะเน็ตเวิร์กเองเลย** — อ่านข้อมูลผ่าน `lsof` อย่างเดียว ผลข้างเคียงเดียวคือการ kill ที่ผู้ใช้กดยืนยันเอง

## วิธีใช้

1. เปิดแอป จะมีไอคอนรูปโครงข่ายบนแถบเมนูด้านขวาบน (ไม่มีใน Dock)
2. กดไอคอน → เห็นรายการโปรแกรมที่เปิด port อยู่
3. กด ▸ หน้าแถวเพื่อดู port ข้างใน
4. เจอตัวที่ไม่ต้องการ → กด **Kill** → **Terminate (SIGTERM)** ถ้าไม่ตายค่อยใช้ **Force Kill (SIGKILL)**
5. ปุ่มเฟืองสำหรับตั้งค่า, ปุ่ม Quit ที่มุมขวาล่างเพื่อออกจากแอป

> Esc ไม่ปิด panel — ให้กดไอคอนบนแถบเมนูอีกครั้ง หรือกดที่อื่นบนจอ

## ติดตั้ง / build

ต้องมี macOS 14 ขึ้นไป และ Xcode (ทดสอบกับ Xcode 27)

```sh
git clone https://github.com/POR-DI/port-watcher.git
cd port-watcher

# build แอป
xcodebuild -project PortWatcher/PortWatcher.xcodeproj -scheme PortWatcher \
  -configuration Debug -derivedDataPath .build/xcode build

# เปิดแอป
open .build/xcode/Build/Products/Debug/PortWatcher.app
```

หรือเปิด `PortWatcher/PortWatcher.xcodeproj` ใน Xcode แล้วกด Run

รันเทสต์ของส่วน logic (70 ข้อ):

```sh
swift test
```

## ข้อจำกัดที่ควรรู้

- **การแจ้งเตือน** (notify เมื่อ port เปิด/ปิด) ยังใช้ไม่ได้กับ build ที่ sign แบบ ad-hoc — macOS ไม่อนุญาต ต้องเพิ่ม Apple ID ใน Xcode → Settings → Accounts แล้วเลือก Team ให้โปรเจกต์ก่อน
- เห็นเฉพาะ process ของ user ที่ล็อกอินอยู่ (`lsof` โดยไม่ใช่ root มองไม่เห็นของ root / user อื่น)
- ปิด "port เดียว" โดยไม่ปิดโปรแกรมไม่ได้ — การ kill คือปิดทั้งโปรแกรม
- ชื่อ service มาจากตารางในตัว + `/etc/services` ของ macOS บาง port อาจได้ชื่อที่ไม่ตรงกับการใช้งานจริง (เช่น 3101 ขึ้น `hp-pxpib`)

## โครงสร้างโปรเจกต์

```
Sources/PortWatcherCore/   logic ทั้งหมด (Swift Package) — สแกน lsof, จับกลุ่ม, filter, kill, view model
Tests/PortWatcherCoreTests/ เทสต์ (Swift Testing)
PortWatcher/               แอป SwiftUI (MenuBarExtra) — มีแต่หน้าจอ ไม่มี logic
docs/superpowers/          spec และแผนงานของแต่ละรอบพัฒนา
scripts/test.sh            รันเทสต์บนเครื่องที่มีแค่ Command Line Tools (ไม่มี Xcode)
```

หลักการ: อะไรที่ทดสอบอัตโนมัติได้อยู่ใน package ทั้งหมด แอปมีหน้าที่แค่แสดงผลและรับคลิก

## สิ่งที่เรียนรู้ระหว่างทำ

- `lsof -F` ให้ output แบบ machine-readable ที่ parse ง่ายกว่าตารางปกติมาก
- process หนึ่งอาจเปิด port เดียวกันซ้ำ 2 บรรทัด (IPv4 + IPv6) ต้อง dedupe
- `MenuBarExtra` แบบ window จะปิดตัวเองทันทีที่คลิกหน้าต่างอื่น — กล่องยืนยัน/alert ของระบบใช้ไม่ได้ ต้องวาดเองในตัว panel
- `getservbyport` ที่หาไม่เจอใช้เวลา ~5 ms ต่อครั้งและไม่ cache — อ่าน `/etc/services` ทีเดียวตอนเริ่มดีกว่า
- `Task` ที่จบแล้ว `await` ไม่ suspend — loop ที่รอมันจะหมุนค้าง main actor ได้

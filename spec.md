# 🧾 BRD Spec – Multi-Station File Uploader with Retry & Telegram Notification

## 1. Overview

ระบบนี้ออกแบบมาเพื่อ **อัปโหลดไฟล์ข้อมูลจากสถานี (station)** บน Windows ไปยัง FTP Server แบบอัตโนมัติทุกวันเวลา 00:05 โดยใช้ **WinSCP + PowerShell + Task Scheduler**

* รองรับหลายสถานี (multi-station)
* มีระบบ log + retry
* แจ้งเตือนผ่าน Telegram
* มี DryRun mode สำหรับทดสอบ mapping

---

## 2. Goals & Objectives

1. ส่งไฟล์ `.gcf` ที่สร้างเมื่อวานไปยัง FTP server โดยอัตโนมัติ
2. หากไฟล์ใดอัปโหลดไม่สำเร็จ ต้องเก็บไว้ใน retry queue และอัปโหลดซ้ำในการรันครั้งต่อไป
3. สรุปผลการทำงานรายวันส่งไปยัง Telegram group/channel
4. ผู้ดูแลสามารถตรวจสอบ log ย้อนหลังได้ และสามารถ dryrun เพื่อดู path ที่จะอัปโหลดได้โดยไม่ส่งจริง

---

## 3. Scope of Work

### In-Scope

* ค้นหาไฟล์ `.gcf` ภายใต้แต่ละ station (ย่อยจาก `BaseFolder`)
* อัปโหลดไฟล์ไปยัง FTP Server ภายใต้ path:

  ```
  /SMA-File-InFraTech/<DeviceName>/<YYYY>/<MM>/<DD>/<filename>
  ```
* รองรับ include/exclude pattern (configurable)
* จัดการ retry queue อัตโนมัติ
* เขียน log และเก็บไม่เกิน N วัน (default 30)
* ส่งผลลัพธ์ไปยัง Telegram

### Out-of-Scope

* ไม่รวมระบบ monitor แบบ real-time
* ไม่รวม web dashboard
* ไม่รวมระบบ retry แบบต่อเนื่อง (เฉพาะรอบถัดไปเท่านั้น)

---

## 4. Functional Requirements

| Requirement               | Description                                      |
| ------------------------- | ------------------------------------------------ |
| **Multi-Station Support** | รองรับการตั้งค่า station หลายตัวใน `config.json` |
| **File Filtering**        | รองรับ include/exclude patterns                  |
| **File Ready Check**      | ตรวจสอบว่าไฟล์พร้อมใช้งาน (`Is-FileReady`)       |
| **Retry Queue**           | เก็บไฟล์ที่อัปโหลดไม่สำเร็จลง `retry-queue.json` |
| **Logging**               | บันทึกการทำงานต่อไฟล์ใน log file (daily log)     |
| **Retention**             | ลบ log เก่าเกิน `LogRetentionDays`               |
| **DryRun Mode**           | พิมพ์ mapping (local → remote) โดยไม่อัปโหลด     |
| **Telegram Notify**       | สรุปผลการอัปโหลด (OK/Fail) ผ่าน Telegram         |
| **Scheduler**             | ตั้ง Task Scheduler ให้รันอัตโนมัติทุกวัน 00:05  |

---

## 5. Non-Functional Requirements

| Category            | Requirement                                                  |
| ------------------- | ------------------------------------------------------------ |
| **OS**              | Windows 8, 10, 11                                            |
| **Tool**            | PowerShell 5+, WinSCP (Portable)                             |
| **Security**        | ซ่อน password ภายใน config.json (file permission restricted) |
| **Scalability**     | รองรับ station ได้ไม่จำกัดตาม config.json                    |
| **Maintainability** | สคริปต์แยก config ออกจากโค้ด, รองรับการแก้ไขง่าย             |

---

## 6. Configurations

**File:** `config.json`

```json
{
  "BaseFolder": "C:\\scream\\data",
  "Stations": [
    { "StationFolder": "5lc400", "DeviceName": "01.SMA-BangNiewDam-01" },
    { "StationFolder": "5lc0n0", "DeviceName": "02.SMA-BangNiewAbutment-02" }
  ],
  "FtpHost": "122.154.8.21",
  "FtpPort": 38866,
  "FtpUser": "FTP-SMA-InFraTech01",
  "FtpPass": "REPLACE_ME",
  "TelegramToken": "123456:REPLACE_ME",
  "TelegramChatId": "-1001234567890",
  "IncludePatterns": ["*.gcf"],
  "ExcludePatterns": ["*.tmp", "*.part", "*.lock"],
  "LogRetentionDays": 30,
  "WinScpPath": "C:\\SyncToCenter\\winscp\\winscp.com",
  "DryRun": false
}
```

---

## 7. Success Criteria

* ระบบอัปโหลดไฟล์ `.gcf` ทุก station ได้ครบถ้วน
* ไฟล์ที่ fail ถูก retry ในรอบถัดไปจนสำเร็จ
* มี log + summary รายวัน
* ได้รับการแจ้งเตือน Telegram ทุกครั้งที่รัน

---

## 8. Future Enhancements (Optional)

* Dashboard แสดงสถานะไฟล์
* Retry แบบ real-time (monitoring + auto-retry)
* Encryption ของ config.json (FTP password)

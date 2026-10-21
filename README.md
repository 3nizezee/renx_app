# AX App — ระบบพัฒนาและ Build ไฟล์ Android APK อัตโนมัติ (Flutter + GitHub Actions)

โปรเจกต์นี้เป็นระบบพัฒนาแอปมือถือด้วย **Flutter** พร้อมระบบ **CI/CD Cloud Build (GitHub Actions)** ที่ช่วยคอมไพล์และสร้างไฟล์ `.apk` ให้คุณอัตโนมัติบนคลาวด์ **โดยที่คุณไม่ต้องติดตั้ง Android Studio หรือ Java ขนาดหลายกิกะไบต์ลงในคอมพิวเตอร์ของคุณเลย!**

---

## 🚀 จุดเด่นของระบบนี้
1. **ไม่ต้องเปลืองพื้นที่ในเครื่อง**: ใช้เครื่องเซิร์ฟเวอร์ฟรีของ GitHub ในการคอมไพล์โค้ดเป็นไฟล์ APK
2. **สร้าง APK ทันทีเมื่อ Push โค้ด**: ทุกครั้งที่คุณบันทึกและส่งโค้ดขึ้น GitHub ระบบจะเริ่มสร้างไฟล์ APK ทันที (ใช้เวลาประมาณ 3–5 นาที)
3. **กดสั่ง Build เมื่อไหร่ก็ได้ (Manual Trigger)**: มีปุ่ม **"Run workflow"** ให้คุณกดสั่งสร้าง APK ได้ตามใจชอบผ่านหน้าเว็บ GitHub
4. **โค้ด Flutter พร้อมต่อยอด**: มีหน้าตา Material 3 สวยงาม, ระบบสลับโหมดมืด/สว่าง (Dark Mode), ฟอร์มรับข้อมูล และตัวอย่าง State Management

---

## 📁 โครงสร้างโปรเจกต์
```
AX_PJ/
├── .github/
│   └── workflows/
│       └── build-apk.yml       # คำสั่งสร้าง APK อัตโนมัติบน GitHub Actions
├── android/                    # การตั้งค่าระบบ Android สำหรับ Gradle Build
├── lib/
│   └── main.dart              # โค้ดหน้าจอหลักของแอปพลิเคชัน Flutter
├── pubspec.yaml                # รายการแพ็กเกจและ dependencies ของ Flutter
├── push_to_github.bat          # สคริปต์ช่วยส่งโค้ดขึ้น GitHub แค่ดับเบิลคลิก
└── README.md                   # คู่มือการใช้งานระบบ
```

---

## 🛠️ ขั้นตอนการสร้างไฟล์ APK (ทำตามได้ทันที)

### ขั้นตอนที่ 1: สร้าง Repository บน GitHub
1. เข้าไปที่ [GitHub.com](https://github.com/) และล็อกอินเข้าสู่ระบบ
2. กดปุ่ม **"+"** ที่มุมขวาบน แล้วเลือก **"New repository"**
3. ตั้งชื่อ Repository เช่น `ax_app`
4. เลือกเป็น **Public** หรือ **Private** ก็ได้
5. **ไม่ต้องติ๊ก** Add README, .gitignore หรือ License (เพราะโปรเจกต์นี้มีให้หมดแล้ว)
6. กดปุ่ม **"Create repository"**
7. คัดลอก URL ของ Repository ไว้ เช่น `https://github.com/your-username/ax_app.git`

---

### ขั้นตอนที่ 2: ส่งโค้ดขึ้น GitHub (Push Code)
เลือกทำวิธีใดวิธีหนึ่ง:

#### วิธีที่ง่ายที่สุด (ผ่านสคริปต์อัตโนมัติ):
- ดับเบิลคลิกที่ไฟล์ `push_to_github.bat` ในโฟลเดอร์นี้
- วาง URL ที่คัดลอกมาจากขั้นตอนที่ 1 แล้วกด Enter

#### หรือทำผ่าน PowerShell / Command Prompt:
```powershell
git remote add origin https://github.com/your-username/ax_app.git
git push -u origin main
```

---

### ขั้นตอนที่ 3: รับและดาวน์โหลดไฟล์ APK
1. กลับไปที่หน้า Repository ของคุณบน GitHub
2. คลิกที่แท็บ **"Actions"** ด้านบน
3. คุณจะเห็น Workflow ชื่อ **"Build Android APK"** กำลังทำงานอยู่ (มีไอคอนสีเหลืองหมุนอยู่)
4. รอประมาณ 3–5 นาที เมื่อเสร็จแล้วจะมีเครื่องหมายถูกสีเขียว (✔️)
5. คลิกเข้าไปที่งานนั้น แล้วเลื่อนลงมาด้านล่างสุดที่หัวข้อ **Artifacts**
6. คลิกดาวน์โหลดไฟล์ **`app-release`** (ข้างในจะมีไฟล์ `app-release.apk` พร้อมติดตั้งลงมือถือ Android ได้ทันที!)

---

## 💡 วิธีแก้ไขและตกแต่งแอปเพิ่มเติม

- **เปลี่ยนหน้าตาหรือฟังก์ชันแอป**: เปิดไฟล์ `lib/main.dart` ด้วยโปรแกรมแก้ไขโค้ด (เช่น VS Code, Notepad) แล้วแก้ข้อความหรือเพิ่ม Widget ตามต้องการ
- **เปลี่ยนชื่อแอป**: เปิดไฟล์ `android/app/src/main/AndroidManifest.xml` แล้วแก้ไขค่า `android:label="ชื่อแอปของคุณ"`
- **ส่งโค้ดอัปเดตเพื่อสร้าง APK เวอร์ชันใหม่**:
  ```powershell
  git add .
  git commit -m "Update app features"
  git push
  ```
  GitHub Actions จะทำการคอมไพล์ APK ใหม่ให้คุณทันที!

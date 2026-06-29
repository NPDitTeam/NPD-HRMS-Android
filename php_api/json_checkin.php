<?php
// ข้อมูลการเชื่อมต่อฐานข้อมูล MySQL
$db_host = 'localhost';
$db_name = 'npdhr_dbbase_npd';
$db_user = 'npdhr_dbbase_npd';
$db_pass = '@Npd78901234';

// ตั้งค่า Header ให้เป็น JSON
header('Content-Type: application/json');

try {
    // อ่านข้อมูลการเข้าสู่ระบบจาก HTTP Basic Authentication
    $username = $_SERVER['PHP_AUTH_USER'] ?? '';
    $password = $_SERVER['PHP_AUTH_PW'] ?? '';

    // ข้อมูลการเข้าสู่ระบบที่ถูกต้อง
    $correct_username = 'Npd_admin';
    $correct_password = '78901234';

    // ตรวจสอบการเข้าสู่ระบบ
    if ($username === $correct_username && $password === $correct_password) {
        // เชื่อมต่อฐานข้อมูล MySQL ด้วย PDO
        $pdo = new PDO("mysql:host=$db_host;dbname=$db_name;charset=utf8", $db_user, $db_pass);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

        // รับ parameter date จาก URL (ถ้าไม่ส่ง = วันนี้)
        // ใช้: ?date=2026-04-06       → ดึงวันเดียว
        //      ?date_from=2026-04-01&date_to=2026-04-07  → ดึงช่วงวัน
        //      ไม่ส่ง                  → ดึงวันนี้
        $date = $_GET['date'] ?? null;
        $date_from = $_GET['date_from'] ?? null;
        $date_to = $_GET['date_to'] ?? null;

        if ($date_from && $date_to) {
            // ดึงช่วงวัน
            $stmt = $pdo->prepare("SELECT * FROM checkin_logs WHERE DATE(checked_at) BETWEEN ? AND ?");
            $stmt->execute([$date_from, $date_to]);
        } elseif ($date) {
            // ดึงวันเดียว
            $stmt = $pdo->prepare("SELECT * FROM checkin_logs WHERE DATE(checked_at) = ?");
            $stmt->execute([$date]);
        } else {
            // ไม่ส่ง = วันนี้
            $today = date('Y-m-d');
            $stmt = $pdo->prepare("SELECT * FROM checkin_logs WHERE DATE(checked_at) = ?");
            $stmt->execute([$today]);
        }

        $checkin_records = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // เตรียม query ดึง employee_code จาก users table
        $user_stmt = $pdo->prepare("SELECT employee_code FROM users WHERE id = ?");

        // สร้าง array ที่จะใช้แปลงเป็น JSON
        $data_to_send = [];
        foreach ($checkin_records as $record) {
            // ดึง employee_code จาก users table
            $employee_code = null;
            if (!empty($record['user_id'])) {
                $user_stmt->execute([$record['user_id']]);
                $user_row = $user_stmt->fetch(PDO::FETCH_ASSOC);
                if ($user_row) {
                    $employee_code = $user_row['employee_code'];
                }
            }

            $data_to_send[] = [
                'user_id' => (string)$record['user_id'],
                'employee_code' => $employee_code,
                'username' => $record['username'],
                'branch' => $record['branch'],
                'check_type' => $record['check_type'],
                'latitude' => $record['latitude'],
                'longitude' => $record['longitude'],
                'checked_at' => $record['checked_at'],
                'department' => $record['department'] ?? 'ไม่ระบุ',
                'position' => $record['position'] ?? 'ไม่ระบุ',
                'date_requested' => date('Y-m-d', strtotime($record['checked_at'])),
                'company' => !empty($record['company']) ? $record['company'] : 'ไม่ระบุบริษัท',
            ];
        }

        // แปลง array เป็น JSON และแสดงผล
        echo json_encode($data_to_send);

    } else {
        // หากการตรวจสอบสิทธิ์ล้มเหลว
        http_response_code(401);
        header('WWW-Authenticate: Basic realm="My API"');
        echo json_encode(['error' => "Unauthorized access. Invalid credentials."]);
    }

} catch (PDOException $e) {
    http_response_code(500);
    echo json_encode(['error' => "ข้อผิดพลาดในการเชื่อมต่อ MySQL: " . $e->getMessage()]);
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => "ข้อผิดพลาดทั่วไป: " . $e->getMessage()]);
}
?>

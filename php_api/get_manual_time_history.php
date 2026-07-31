<?php
// get_manual_time_history.php
// ประวัติการขอเพิ่มเวลาทั้งหมดของพนักงาน 1 คน กรองตามเดือน/ปี (ไม่มี LIMIT)
// ใช้กับปุ่ม "แสดงทั้งหมด" ในหน้าประวัติการเพิ่มเวลาของแอป
//
// GET: ?user_id=1&month=7&year=2026
//  - month/year เป็น ค.ศ. (แอปส่ง DateTime.now().year มาให้)
//  - ถ้าไม่ส่ง month/year มา จะคืนทั้งหมดของ user คนนั้น
//
// รูปแบบ JSON ที่คืน ต้องตรงกับ AddTimeLog.fromJson ในแอป

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

ini_set('display_errors', 0);
ini_set('log_errors', 1);
error_reporting(E_ALL);

$host   = 'localhost';
$dbname = 'npdhr_dbbase_npd';
$dbuser = 'npdhr_dbbase_npd';
$dbpass = '@Npd78901234';

function send_json($status, $message, $data = [])
{
    echo json_encode(
        ['status' => $status, 'message' => $message, 'data' => $data],
        JSON_UNESCAPED_UNICODE
    );
    exit();
}

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8", $dbuser, $dbpass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
} catch (PDOException $e) {
    error_log('get_manual_time_history DB error: ' . $e->getMessage());
    send_json('error', 'Database connection failed.');
}

$userId = isset($_GET['user_id']) ? (int)$_GET['user_id'] : 0;
$month  = isset($_GET['month']) ? (int)$_GET['month'] : 0;
$year   = isset($_GET['year']) ? (int)$_GET['year'] : 0;

if ($userId <= 0) {
    send_json('error', 'User ID is required.');
}

// กรองตามเดือน/ปีของวันที่ทำงาน
$where  = 'mtl.user_id = ?';
$params = [$userId];

if ($year > 0) {
    $where .= ' AND YEAR(mtl.work_date) = ?';
    $params[] = $year;
}
if ($month >= 1 && $month <= 12) {
    $where .= ' AND MONTH(mtl.work_date) = ?';
    $params[] = $month;
}

try {
    $sql = "
        SELECT
            mtl.id, mtl.user_id, mtl.username, mtl.work_date,
            mtl.checkin_time, mtl.checkout_time,
            mtl.department, mtl.position, mtl.company,
            mtl.state, mtl.created_at, mtl.reason, mtl.user_note,
            mtl.reason_type, mtl.allowance_type, mtl.amount, mtl.file_path,
            mtl.approved_by, mtl.approved_at,
            appr.firstname AS approver_firstname,
            appr.lastname  AS approver_lastname
        FROM manual_time_logs mtl
        LEFT JOIN users appr ON mtl.approved_by = appr.id
        WHERE $where
        ORDER BY mtl.work_date DESC, mtl.id DESC
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // จัดรูปเวลาให้เป็น HH:mm ตามที่ AddTimeLog.fromJson คาดหวัง
    foreach ($rows as &$r) {
        if (!empty($r['checkin_time'])) {
            $r['checkin_time'] = date('H:i', strtotime($r['checkin_time']));
        }
        if (!empty($r['checkout_time'])) {
            $r['checkout_time'] = date('H:i', strtotime($r['checkout_time']));
        }
    }
    unset($r);

    send_json('success', 'Manual time history fetched successfully.', $rows);
} catch (PDOException $e) {
    error_log('get_manual_time_history query error: ' . $e->getMessage());
    send_json('error', 'ไม่สามารถดึงข้อมูลประวัติการเพิ่มเวลาได้');
}

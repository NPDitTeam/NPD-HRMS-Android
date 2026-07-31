<?php
// get_leave_history.php
// ประวัติการลาทั้งหมดของพนักงาน 1 คน กรองตามเดือน/ปี (ไม่มี LIMIT)
// ใช้กับปุ่ม "แสดงทั้งหมด" ในหน้าประวัติการลาของแอป
//
// GET: ?user_id=1&month=7&year=2026
//  - month/year เป็น ค.ศ. (แอปส่ง DateTime.now().year มาให้)
//  - ถ้าไม่ส่ง month/year มา จะคืนทั้งหมดของ user คนนั้น
//
// รูปแบบ JSON ที่คืน ต้องตรงกับ LeaveLog.fromJson ในแอป
// (สังเกตชื่อคอลัมน์ leave_statr_time — เป็นชื่อจริงในตาราง ห้ามแก้)

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
    error_log('get_leave_history DB error: ' . $e->getMessage());
    send_json('error', 'Database connection failed.');
}

$userId = isset($_GET['user_id']) ? (int)$_GET['user_id'] : 0;
$month  = isset($_GET['month']) ? (int)$_GET['month'] : 0;
$year   = isset($_GET['year']) ? (int)$_GET['year'] : 0;

if ($userId <= 0) {
    send_json('error', 'User ID is required.');
}

// กรองตามเดือน/ปีของวันที่เริ่มลา
$where  = 'lr.user_id = ?';
$params = [$userId];

if ($year > 0) {
    $where .= ' AND YEAR(lr.leave_start_date) = ?';
    $params[] = $year;
}
if ($month >= 1 && $month <= 12) {
    $where .= ' AND MONTH(lr.leave_start_date) = ?';
    $params[] = $month;
}

try {
    $sql = "
        SELECT
            lr.id, lr.user_id, lr.username,
            lr.leave_start_date, lr.leave_statr_time,
            lr.leave_end_date, lr.leave_end_time,
            lr.leave_type, lr.note, lr.file_path, lr.state, lr.reason,
            lr.approved_by, lr.approved_at, lr.created_at,
            lr.department, lr.position,
            u.branch, u.firstname, u.lastname,
            appr.firstname AS approver_firstname,
            appr.lastname  AS approver_lastname
        FROM leave_requests lr
        LEFT JOIN users u    ON lr.user_id     = u.id
        LEFT JOIN users appr ON lr.approved_by = appr.id
        WHERE $where
        ORDER BY lr.leave_start_date DESC, lr.id DESC
    ";

    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
    $rows = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // จัดรูปเวลาให้เป็น HH:mm ตามที่ LeaveLog.fromJson คาดหวัง
    foreach ($rows as &$r) {
        if (!empty($r['leave_statr_time'])) {
            $r['leave_statr_time'] = date('H:i', strtotime($r['leave_statr_time']));
        }
        if (!empty($r['leave_end_time'])) {
            $r['leave_end_time'] = date('H:i', strtotime($r['leave_end_time']));
        }
    }
    unset($r);

    send_json('success', 'Leave history fetched successfully.', $rows);
} catch (PDOException $e) {
    error_log('get_leave_history query error: ' . $e->getMessage());
    send_json('error', 'ไม่สามารถดึงข้อมูลประวัติการลาได้');
}

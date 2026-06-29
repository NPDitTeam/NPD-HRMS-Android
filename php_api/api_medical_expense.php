<?php
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(200);
    exit();
}

// Database connection
$host = 'localhost';
$dbname = 'npdhr_dbbase_npd';
$user = 'npdhr_dbbase_npd';
$pass = '@Npd78901234';

try {
    $pdo = new PDO("mysql:host=$host;dbname=$dbname;charset=utf8", $user, $pass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException $e) {
    echo json_encode(['status' => 'error', 'message' => 'Database connection failed: ' . $e->getMessage()]);
    exit();
}

// ============================================================
// GET: ดึงรายการค่ารักษาพยาบาลทั้งหมด
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    try {
        $stmt = $pdo->prepare("
            SELECT
                mtl.id, mtl.user_id, mtl.username, mtl.work_date,
                mtl.checkin_time, mtl.checkout_time,
                mtl.department, mtl.position, mtl.company,
                mtl.state, mtl.created_at, mtl.reason,
                mtl.user_note, mtl.reason_type, mtl.amount, mtl.file_path,
                mtl.approved_by, mtl.approved_at,
                u.employee_code, u.branch,
                appr.firstname AS approver_firstname,
                appr.lastname AS approver_lastname
            FROM manual_time_logs mtl
            LEFT JOIN users u ON mtl.user_id = u.id
            LEFT JOIN users appr ON mtl.approved_by = appr.id
            WHERE mtl.reason_type = 'ค่ารักษาพยาบาล'
            ORDER BY mtl.created_at DESC
        ");
        $stmt->execute();
        $logs = $stmt->fetchAll(PDO::FETCH_ASSOC);

        // Format time
        foreach ($logs as &$log) {
            if (!empty($log['checkin_time'])) {
                $log['checkin_time'] = date('H:i', strtotime($log['checkin_time']));
            }
            if (!empty($log['checkout_time'])) {
                $log['checkout_time'] = date('H:i', strtotime($log['checkout_time']));
            }
        }
        unset($log);

        echo json_encode(['status' => 'success', 'data' => $logs]);
    } catch (PDOException $e) {
        echo json_encode(['status' => 'error', 'message' => 'Failed to fetch data: ' . $e->getMessage()]);
    }
    exit();
}

// ============================================================
// POST: อนุมัติ / ไม่อนุมัติ / ยกเลิก
// ============================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // รับ JSON body
    $input = json_decode(file_get_contents('php://input'), true);
    if (!$input) {
        // ลอง form data
        $input = $_POST;
    }

    $requestId = intval($input['request_id'] ?? 0);
    $action = trim($input['action'] ?? '');
    $reason = trim($input['reason'] ?? '');

    if ($requestId <= 0) {
        echo json_encode(['status' => 'error', 'message' => 'ไม่พบ ID คำขอ']);
        exit();
    }

    if (!in_array($action, ['approve', 'reject', 'cancel'])) {
        echo json_encode(['status' => 'error', 'message' => 'การกระทำไม่ถูกต้อง (approve/reject/cancel)']);
        exit();
    }

    try {
        $pdo->beginTransaction();

        $newState = '';
        $message = '';

        switch ($action) {
            case 'approve':
                $newState = 'อนุมัติ';
                $message = 'อนุมัติค่ารักษาพยาบาลเรียบร้อยแล้ว';
                break;
            case 'reject':
                $newState = 'ไม่อนุมัติ';
                $message = 'ไม่อนุมัติค่ารักษาพยาบาลเรียบร้อยแล้ว';
                break;
            case 'cancel':
                $newState = 'ยกเลิก';
                $message = 'ยกเลิกค่ารักษาพยาบาลเรียบร้อยแล้ว';
                break;
        }

        $stmt = $pdo->prepare("
            UPDATE manual_time_logs
            SET state = ?,
                reason = ?,
                approved_at = NOW()
            WHERE id = ?
              AND reason_type = 'ค่ารักษาพยาบาล'
        ");
        $stmt->execute([$newState, $reason, $requestId]);

        if ($stmt->rowCount() > 0) {
            $pdo->commit();
            echo json_encode(['status' => 'success', 'message' => $message]);
        } else {
            $pdo->rollBack();
            echo json_encode(['status' => 'error', 'message' => 'ไม่พบคำขอที่สามารถดำเนินการได้']);
        }
    } catch (PDOException $e) {
        $pdo->rollBack();
        echo json_encode(['status' => 'error', 'message' => 'Database error: ' . $e->getMessage()]);
    }
    exit();
}

echo json_encode(['status' => 'error', 'message' => 'Invalid request method.']);
?>

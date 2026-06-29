<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
  http_response_code(200);
  exit();
}

session_start();

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

function get_input($key, $default = null) {
   if (isset($_GET[$key])) return $_GET[$key];
   if (isset($_POST[$key])) return $_POST[$key];
   $json_data = file_get_contents('php://input');
   $decoded_data = json_decode($json_data, true);
   if (isset($decoded_data[$key])) return $decoded_data[$key];
   return $default;
}

// === GET: Fetch logs ===
if ($_SERVER['REQUEST_METHOD'] === 'GET') {
   $userId = get_input('user_id');
   if (!$userId) {
      echo json_encode(['status' => 'error', 'message' => 'User ID is required.']);
      exit();
   }

   try {
      $stmt = $pdo->prepare("
        SELECT mtl.id, mtl.user_id, mtl.username, mtl.work_date, mtl.checkin_time, mtl.checkout_time,
               mtl.department, mtl.position, mtl.company, mtl.state, mtl.created_at, mtl.reason, mtl.user_note,
               mtl.reason_type, mtl.allowance_type, mtl.amount, mtl.file_path,
               mtl.approved_by, mtl.approved_at,
               appr.firstname AS approver_firstname,
               appr.lastname AS approver_lastname
        FROM manual_time_logs mtl
        LEFT JOIN users appr ON mtl.approved_by = appr.id
        WHERE mtl.user_id = ?
        ORDER BY mtl.created_at DESC
        LIMIT 7
      ");
      $stmt->execute([$userId]);
      $logs = $stmt->fetchAll(PDO::FETCH_ASSOC);
      echo json_encode(['status' => 'success', 'data' => $logs]);
   } catch (PDOException $e) {
      echo json_encode(['status' => 'error', 'message' => 'Failed to fetch logs: ' . $e->getMessage()]);
   }
   exit();
}

// === POST: Save/Update log ===
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $requestId     = get_input('request_id');
    $userId        = get_input('user_id');
    $workDate      = get_input('work_date');
    $checkinTime   = get_input('checkin_time');
    $checkoutTime  = get_input('checkout_time');
    $userNote      = get_input('user_note');
    $reasonType    = get_input('reason_type');
    $allowanceType = get_input('allowance_type');
    $amount        = get_input('amount');

    // ทำให้ allowance_type เป็น NULL ถ้าเป็นค่าว่าง
    if ($allowanceType !== null) {
        $allowanceType = trim($allowanceType);
        if ($allowanceType === '') {
            $allowanceType = null;
        }
    }

    // แปลง amount เป็นตัวเลข (ถ้ามี)
    $amountValue = null;
    if (!empty($amount) && is_numeric($amount)) {
        $amountValue = floatval($amount);
    }

    if (!$userId || !$workDate || !$checkinTime || !$checkoutTime) {
        echo json_encode(['status' => 'error', 'message' => 'Missing required fields']);
        exit();
    }

    // ตรวจสอบ: ถ้าเป็นค่าเบี๊ยเลี้ยงฯ หรือค่ารักษาพยาบาล ต้องมีจำนวนเงิน
    if (($reasonType === 'ค่าเบี๊ยเลี้ยงออกนอกสถานที่' || $reasonType === 'ค่ารักษาพยาบาล') && ($amountValue === null || $amountValue <= 0)) {
        echo json_encode(['status' => 'error', 'message' => 'กรุณากรอกจำนวนเงิน']);
        exit();
    }

    $username = $department = $position = $company = 'N/A';

    try {
        $stmtUser = $pdo->prepare("SELECT firstname, lastname, department, position, company FROM users WHERE id = ?");
        $stmtUser->execute([$userId]);
        $userData = $stmtUser->fetch(PDO::FETCH_ASSOC);

        if ($userData) {
            $username   = $userData['firstname'] . ' ' . $userData['lastname'];
            $department = $userData['department'];
            $position   = $userData['position'];
            $company    = $userData['company'];
        } else {
            echo json_encode(['status' => 'error', 'message' => 'User not found.']);
            exit();
        }

        // === File Upload Validation ===
        $filePath = null;
        if (!empty($_FILES['file']['name'])) {
            $allowedTypes = ['jpg','jpeg','png','pdf'];
            $maxFileSize  = 5 * 1024 * 1024; // 5MB

            $fileExt = strtolower(pathinfo($_FILES['file']['name'], PATHINFO_EXTENSION));
            $fileSize = $_FILES['file']['size'];

            if (!in_array($fileExt, $allowedTypes)) {
                echo json_encode(['status' => 'error', 'message' => 'รองรับเฉพาะไฟล์ JPG, PNG, PDF เท่านั้น']);
                exit();
            }

            if ($fileSize > $maxFileSize) {
                echo json_encode(['status' => 'error', 'message' => 'ไฟล์ต้องมีขนาดไม่เกิน 5MB']);
                exit();
            }

            $uploadDir = __DIR__ . '/uploads/manual_time_logs/';
            if (!is_dir($uploadDir)) mkdir($uploadDir, 0777, true);

            $fileName   = time() . '_' . basename($_FILES['file']['name']);
            $targetFile = $uploadDir . $fileName;

            if (move_uploaded_file($_FILES['file']['tmp_name'], $targetFile)) {
                $filePath = 'uploads/manual_time_logs/' . $fileName;
            }
        }

        if ($requestId) {
            $stmtCheckState = $pdo->prepare("SELECT state, file_path FROM manual_time_logs WHERE id = ? AND user_id = ?");
            $stmtCheckState->execute([$requestId, $userId]);
            $row = $stmtCheckState->fetch(PDO::FETCH_ASSOC);

            if ($row && $row['state'] === 'รออนุมัติ') {
                if ($filePath !== null && !empty($row['file_path']) && file_exists(__DIR__ . '/' . $row['file_path'])) {
                    unlink(__DIR__ . '/' . $row['file_path']);
                }
                if ($filePath === null) {
                    $filePath = $row['file_path'];
                }

                $stmtUpdate = $pdo->prepare("
                    UPDATE manual_time_logs
                    SET work_date = ?, checkin_time = ?, checkout_time = ?,
                        user_note = ?, reason_type = ?, allowance_type = ?, amount = ?, file_path = ?,
                        created_at = NOW(), state = 'รออนุมัติ'
                    WHERE id = ? AND user_id = ?
                ");
                $stmtUpdate->execute([
                    $workDate, $checkinTime, $checkoutTime,
                    $userNote, $reasonType, $allowanceType, $amountValue, $filePath,
                    $requestId, $userId
                ]);

                echo json_encode(['status' => 'success', 'message' => 'แก้ไขเวลาเรียบร้อยแล้ว']);
            } else {
                echo json_encode(['status' => 'error', 'message' => 'ไม่สามารถแก้ไขได้เนื่องจากสถานะไม่ใช่ "รออนุมัติ"']);
            }
        } else {
            $stmtInsert = $pdo->prepare("
                INSERT INTO manual_time_logs
                (user_id, username, work_date, checkin_time, checkout_time, department, position, company, user_note, reason_type, allowance_type, amount, file_path, state, created_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
            ");
            $stmtInsert->execute([
                $userId, $username, $workDate, $checkinTime, $checkoutTime,
                $department, $position, $company, $userNote, $reasonType, $allowanceType, $amountValue, $filePath, 'รออนุมัติ'
            ]);
            echo json_encode(['status' => 'success', 'message' => 'บันทึกเวลาเรียบร้อยแล้ว, กรุณารอการอนุมัติ']);
        }
    } catch (PDOException $e) {
        echo json_encode(['status' => 'error', 'message' => 'Database operation failed: ' . $e->getMessage()]);
    }
    exit();
}

echo json_encode(['status' => 'error', 'message' => 'Invalid request method.']);
?>

<?php
// approve_add_time_screen.php - API Endpoint for Approver to manage Manual Time Logs
header('Content-Type: application/json'); // Ensure JSON response
ini_set('display_errors', 1);             // Enable display errors for debugging (CHANGE TO 0 IN PRODUCTION!)
ini_set('log_errors', 1);                 // Enable error logging
error_reporting(E_ALL);                   // Report all errors

// --- Database Connection Configuration - CHANGE THESE TO YOUR ACTUAL DB CREDENTIALS ---
define('DB_HOST', 'localhost');
define('DB_NAME', 'npdhr_dbbase_npd');
define('DB_USER', 'npdhr_dbbase_npd');
define('DB_PASS', '@Npd78901234');

// Function to handle database connection
function getPdoConnection() {
    try {
        $pdo = new PDO("mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8", DB_USER, DB_PASS);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        $pdo->setAttribute(PDO::ATTR_EMULATE_PREPARES, false);
        return $pdo;
    } catch (PDOException $e) {
        error_log("DB Connection Error: " . $e->getMessage());
        echo json_encode(['status' => 'error', 'message' => 'Database connection failed.']);
        exit(); // Exit immediately on DB connection error
    }
}

$pdo = getPdoConnection();

// Function to send JSON response
function sendJsonResponse($status, $message, $data = []) {
    echo json_encode(['status' => $status, 'message' => $message, 'data' => $data]);
    exit(); // Always exit after sending JSON response
}

// Get the logged-in user's ID from the request (Flutter will pass this via GET/POST)
$loggedInUserId = $_GET['user_id'] ?? $_POST['user_id'] ?? null;
if (!$loggedInUserId) {
    sendJsonResponse('error', 'User ID is required.');
}

// Check if the logged-in user has approver roles AND get the list of user_ids they can approve
$isApprover = false;
$usersToApproveByThisApprover = []; // Initialize an empty array
try {
    $stmtGetApprovedUsers = $pdo->prepare("SELECT user_id FROM approver_relations WHERE approver_user_id = ?");
    $stmtGetApprovedUsers->execute([$loggedInUserId]);
    $usersToApproveByThisApprover = $stmtGetApprovedUsers->fetchAll(PDO::FETCH_COLUMN); // Fetch just the user_id column

    if (!empty($usersToApproveByThisApprover)) {
        $isApprover = true;
    }
} catch (PDOException $e) {
    error_log("Error checking approver status and fetching relations: " . $e->getMessage());
    sendJsonResponse('error', 'Failed to verify approver status.');
}

// If the user is not an approver, deny access
if (!$isApprover) {
    sendJsonResponse('error', 'คุณไม่มีสิทธิ์เข้าถึงหน้านี้');
}


// --- POST Handling for Approval/Disapproval/Edit Actions (from Flutter) ---
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    $requestId = (int)($_POST['request_id'] ?? 0);
    $action = $_POST['action'];
    $reason = trim($_POST['reason'] ?? '');
    $newState = trim($_POST['new_state'] ?? '');

    if ($requestId <= 0) {
        sendJsonResponse('error', 'ไม่พบ ID คำขอ');
    }

    try {
        $pdo->beginTransaction();

        $updateSql = "";
        $params = [
            ':approved_by' => $loggedInUserId,
            ':request_id' => $requestId
        ];

        // -------------------------------------------------------------
        // A C T I O N : A P P R O V E (Approve a pending request)
        // -------------------------------------------------------------
        if ($action === 'approve') {
            // ตรวจสอบว่าคำขอนี้เป็นประเภท "ค่ารักษาพยาบาล" หรือไม่
            $stmtCheck = $pdo->prepare("SELECT reason_type FROM manual_time_logs WHERE id = ?");
            $stmtCheck->execute([$requestId]);
            $reqData = $stmtCheck->fetch(PDO::FETCH_ASSOC);

            if ($reqData && $reqData['reason_type'] === 'ค่ารักษาพยาบาล') {
                $pdo->rollBack();
                sendJsonResponse('error', 'คำขอประเภท "ค่ารักษาพยาบาล" ไม่สามารถอนุมัติผ่านแอปได้ กรุณาอนุมัติผ่านระบบอื่น');
            }

            $updateSql = "
                UPDATE manual_time_logs
                SET
                    state = 'อนุมัติ',
                    reason = NULL,
                    approved_by = :approved_by,
                    approved_at = NOW()
                WHERE id = :request_id AND state = 'รออนุมัติ'
            ";

            $stmtUpdate = $pdo->prepare($updateSql);
            $stmtUpdate->execute($params);

            if ($stmtUpdate->rowCount() > 0) {
                $pdo->commit();
                sendJsonResponse('success', "ดำเนินการอนุมัติคำขอเพิ่มเวลาเรียบร้อยแล้ว");
            } else {
                $pdo->rollBack();
                sendJsonResponse('error', "ไม่พบคำขอ หรือสถานะคำขอไม่อยู่ในสถานะ 'รออนุมัติ'");
            }
        }
        // -------------------------------------------------------------
        // A C T I O N : D I S A P P R O V E (Disapprove a pending request)
        // -------------------------------------------------------------
        elseif ($action === 'disapprove') {
            $updateSql = "
                UPDATE manual_time_logs
                SET
                    state = 'ไม่อนุมัติ',
                    reason = :reason,
                    approved_by = :approved_by,
                    approved_at = NOW()
                WHERE id = :request_id AND state = 'รออนุมัติ'
            ";
            $params[':reason'] = empty($reason) ? 'ไม่มีเหตุผล' : $reason;

            $stmtUpdate = $pdo->prepare($updateSql);
            $stmtUpdate->execute($params);

            if ($stmtUpdate->rowCount() > 0) {
                $pdo->commit();
                sendJsonResponse('success', "ดำเนินการไม่อนุมัติคำขอเพิ่มเวลาเรียบร้อยแล้ว");
            } else {
                $pdo->rollBack();
                sendJsonResponse('error', "ไม่พบคำขอ หรือสถานะคำขอไม่อยู่ในสถานะ 'รออนุมัติ'");
            }
        }
        // -------------------------------------------------------------
        // A C T I O N : E D I T _ S T A T U S (Change state directly)
        // -------------------------------------------------------------
        elseif ($action === 'edit_status') {
            if (!$newState) {
                sendJsonResponse('error', 'สถานะใหม่เป็นค่าว่าง');
            }
            $updateSql = "
                UPDATE manual_time_logs
                SET
                    state = :new_state,
                    reason = :reason,
                    approved_by = :approved_by,
                    approved_at = NOW()
                WHERE id = :request_id
            ";
            $params[':new_state'] = $newState;
            $params[':reason'] = empty($reason) ? '' : $reason;

            $stmtUpdate = $pdo->prepare($updateSql);
            $stmtUpdate->execute($params);

            if ($stmtUpdate->rowCount() > 0) {
                $pdo->commit();
                sendJsonResponse('success', "ดำเนินการแก้ไขสถานะคำขอเรียบร้อยแล้ว");
            } else {
                $pdo->rollBack();
                sendJsonResponse('error', "ไม่พบคำขอที่สามารถแก้ไขได้");
            }
        } else {
            sendJsonResponse('error', "การกระทำไม่ถูกต้อง");
        }
    } catch (PDOException $e) {
        $pdo->rollBack();
        error_log("Approval/Disapproval/Edit error: " . $e->getMessage());
        sendJsonResponse('error', "ข้อผิดพลาดในการดำเนินการ: " . $e->getMessage());
    } catch (Exception $e) {
        $pdo->rollBack();
        error_log("General error in POST handling: " . $e->getMessage());
        sendJsonResponse('error', "เกิดข้อผิดพลาด: " . $e->getMessage());
    }
}
// --- GET Handling (Fetch Pending and History Requests for display) ---
else if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $pendingRequests = [];
    $historyRequests = [];

    try {
        // Build the IN clause for user_ids this approver can approve
        $inClause = '';
        $inClauseParams = [];
        if (!empty($usersToApproveByThisApprover)) {
            $inClause = ' AND mtl.user_id IN (' . implode(',', array_fill(0, count($usersToApproveByThisApprover), '?')) . ')';
            $inClauseParams = $usersToApproveByThisApprover;
        } else {
            // If the approver cannot approve anyone, return empty lists
            sendJsonResponse('success', 'Requests fetched successfully.', [
                'pending_requests' => [],
                'history_requests' => []
            ]);
        }

        // Fetch Pending Requests (ไม่รวม "ค่ารักษาพยาบาล" เพราะอนุมัติที่อื่น)
        $stmtRequests = $pdo->prepare("
            SELECT
                mtl.id, mtl.user_id, u.firstname, u.lastname,
                mtl.work_date, mtl.checkin_time, mtl.checkout_time,
                mtl.department, mtl.position, u.branch,
                mtl.state, mtl.created_at, mtl.reason, mtl.username, mtl.reason_type, mtl.allowance_type, mtl.amount, mtl.file_path,
                appr.firstname AS approver_firstname, appr.lastname AS approver_lastname
            FROM manual_time_logs mtl
            JOIN users u ON mtl.user_id = u.id
            LEFT JOIN users appr ON mtl.approved_by = appr.id
            WHERE mtl.state = 'รออนุมัติ'
              AND mtl.reason_type != 'ค่ารักษาพยาบาล'
              AND mtl.user_id != ?
              $inClause
            ORDER BY mtl.created_at ASC
        ");

        // Prepare parameters for the pending requests query
        $paramsPending = [$loggedInUserId]; // First positional parameter
        if (!empty($inClauseParams)) {
            $paramsPending = array_merge($paramsPending, $inClauseParams);
        }
        $stmtRequests->execute($paramsPending);
        $pendingRequests = $stmtRequests->fetchAll(PDO::FETCH_ASSOC);

        // Fetch History Requests (Approved/Disapproved in last 7 days)
        $stmtHistory = $pdo->prepare("
            SELECT
                mtl.id, mtl.user_id, u.firstname, u.lastname,
                mtl.work_date, mtl.checkin_time, mtl.checkout_time,
                mtl.department, mtl.position, u.branch,
                mtl.state, mtl.created_at, mtl.reason, mtl.approved_at, mtl.username, mtl.reason_type, mtl.allowance_type, mtl.amount, mtl.file_path,
                appr.firstname AS approver_firstname, appr.lastname AS approver_lastname
            FROM manual_time_logs mtl
            JOIN users u ON mtl.user_id = u.id
            LEFT JOIN users appr ON mtl.approved_by = appr.id
            WHERE (mtl.state = 'อนุมัติ' OR mtl.state = 'ไม่อนุมัติ')
              AND mtl.approved_at >= CURDATE() - INTERVAL 7 DAY
              AND mtl.user_id != ?
              $inClause
            ORDER BY mtl.approved_at DESC
        ");

        // Prepare parameters for the history requests query
        $paramsHistory = [$loggedInUserId]; // First positional parameter
        if (!empty($inClauseParams)) {
            $paramsHistory = array_merge($paramsHistory, $inClauseParams);
        }
        $stmtHistory->execute($paramsHistory);
        $historyRequests = $stmtHistory->fetchAll(PDO::FETCH_ASSOC);

        // Format dates/times for Flutter if needed (example: TimeOfDay expects HH:mm)
        foreach ($pendingRequests as &$req) {
            $req['checkin_time'] = date('H:i', strtotime($req['checkin_time']));
            $req['checkout_time'] = date('H:i', strtotime($req['checkout_time']));
        }
        unset($req);
        foreach ($historyRequests as &$req) {
            $req['checkin_time'] = date('H:i', strtotime($req['checkin_time']));
            $req['checkout_time'] = date('H:i', strtotime($req['checkout_time']));
        }
        unset($req);


        sendJsonResponse('success', 'Requests fetched successfully.', [
            'pending_requests' => $pendingRequests,
            'history_requests' => $historyRequests
        ]);

    } catch (PDOException $e) {
        error_log("Error fetching requests for approver: " . $e->getMessage());
        sendJsonResponse('error', "ไม่สามารถดึงข้อมูลคำขอได้: " . $e->getMessage());
    }

} else {
    sendJsonResponse('error', 'Invalid request method. Only GET and POST are supported.');
}
?>

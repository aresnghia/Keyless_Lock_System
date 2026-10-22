// =============================================================================
// Common_Params.v
// File định nghĩa chung cho toàn nhóm
// =============================================================================

// --- MÃ PHÍM SỐ (Hex 4-bit) ---
`define KEY_0    4'h0
`define KEY_1    4'h1
`define KEY_2    4'h2
`define KEY_3    4'h3
`define KEY_4    4'h4
`define KEY_5    4'h5
`define KEY_6    4'h6
`define KEY_7    4'h7
`define KEY_8    4'h8
`define KEY_9    4'h9

// --- MÃ PHÍM CHỨC NĂNG (Khớp với Keypad 123A/456B/789C) ---
`define KEY_ENT  4'hA  // Phím A: Enter (Xác nhận)
`define KEY_BACK 4'hB  // Phím B: Backspace (Xóa lùi 1 ký tự)
`define KEY_CLR  4'hC  // Phím C: Clear (Xóa sạch toàn bộ)
`define KEY_HIDE 4'hD  // Phím D: Hide/Show (Ẩn/Hiện mật khẩu)
`define KEY_NONE 4'hF  // Trạng thái không có phím nào được nhấn

// =============================================================================
// LCD MESSAGES LIBRARY (Mỗi thông điệp phải dài ĐÚNG 16 ký tự)
// =============================================================================

// --- Trạng thái cơ bản ---
`define MSG_WELCOME  "WELCOME TO LAB  "
`define MSG_IDLE     "ENTER PASSWORD: "
`define MSG_CORRECT  "ACCESS GRANTED  "
`define MSG_WRONG    "WRONG PASSWORD! "

// --- Trạng thái cài đặt & đổi pass ---
`define MSG_SET_INIT "SET INITIAL PWD "
`define MSG_SET_NEW  "SET NEW PASS:   "
`define MSG_CHG_OLD  "ENTER OLD PASS: "
`define MSG_CHG_NEW  "NEW PWD MODE:   "

// --- Trạng thái khóa & mở ---
`define MSG_LOCKED   "SYSTEM LOCKED!  "
`define MSG_UNLOCKED "DOOR IS OPENED  "
`define MSG_CLEAR    "                " // Đủ 16 khoảng trắng để xóa sạch dòng
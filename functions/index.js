const functions = require("firebase-functions");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

const axios = require("axios"); // axios 추가 필요

admin.initializeApp();

/**
 * 외부 RSS 데이터를 대신 긁어오는 프록시 함수 (CORS 우회용)
 */
exports.fetchRssData = functions.https.onCall(async (data, context) => {
  const { url } = data;
  if (!url) throw new functions.https.HttpsError("invalid-argument", "URL이 없습니다.");

  try {
    const response = await axios.get(url, {
      timeout: 10000,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
      }
    });
    return { success: true, data: response.data };
  } catch (error) {
    console.error("RSS Fetch Error:", error);
    return { success: false, error: error.message };
  }
});

/**
 * Flutter 앱에서 직접 호출하는 Callable 함수
 */
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: "your-email@gmail.com",
    pass: "your-app-password",
  },
});

/**
 * Flutter 앱에서 직접 호출하는 Callable 함수
 */
exports.sendNewsEmail = functions.https.onCall(async (data, context) => {
  // 클라이언트(Flutter)에서 보낸 데이터 추출
  const { email, htmlContent, subject } = data;

  if (!email || !htmlContent || !subject) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "필수 파라미터(email, htmlContent, subject)가 누락되었습니다."
    );
  }

  const mailOptions = {
    from: "News Crawler <your-email@gmail.com>",
    to: email,
    subject: subject,
    html: htmlContent,
  };

  try {
    const info = await transporter.sendMail(mailOptions);
    console.log("Email sent: " + info.response);
    return {
      success: true,
      message: "이메일이 성공적으로 발송되었습니다."
    };
  } catch (error) {
    console.error("이메일 발송 중 에러 발생:", error);
    throw new functions.https.HttpsError(
      "internal",
      "이메일 발송에 실패했습니다: " + error.message
    );
  }
});

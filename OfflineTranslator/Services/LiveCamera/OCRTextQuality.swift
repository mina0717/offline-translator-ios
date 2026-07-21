import Foundation

/// v1.4.0 hotfix4：OCR 結果的品質把關。
///
/// 起因：QA 影片裡黑框內出現 `L)Iyx*ii'li IMI'K%ilik{Jii(I Imjiiwai #atI()ii` 這種東西。
/// 那不是翻譯壞掉 —— 是 Vision 對著螢幕小字辨識出亂碼，Apple Translation 忠實地
/// 把亂碼「翻譯」成另一串亂碼，然後用一個大黑框蓋在畫面上。
///
/// 單靠 `candidate.confidence` 擋不住：Vision 對亂碼常常給出頗高的信心值。
/// 所以這裡再加一層「這串字看起來像不像人類語言」的字面結構檢查。
///
/// 取捨：寧可濾掉一些邊緣的真文字，也不要讓亂碼上畫面。
/// 沒翻到只是少一塊，翻出亂碼會讓整個功能看起來是壞的。
enum OCRTextQuality {

    /// 低於這個信心直接丟。原本 0.3 太寬鬆，是亂碼大量湧入的主因。
    static let minConfidence: Float = 0.45

    /// 文字高度佔畫面比例的下限。太小的字辨識率極低，
    /// 只會製造抖動又看不清楚，不如不辨識。
    static let minTextHeight: Float = 0.015

    /// 這串文字看起來像不像真的語言？四關全過才算數。
    static func looksLikeRealText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return false }

        let scalars = Array(trimmed.unicodeScalars)

        // 1. 有意義字元（字母／數字／空白）比例 —— 亂碼的特徵是夾雜大量 )(*#{}| 符號
        let meaningful = scalars.filter {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }.count
        guard Double(meaningful) / Double(scalars.count) >= 0.65 else { return false }

        // 2. 字母比例 —— 擋掉 `11111s1#1)t>iixlv# (M it>¥1 Iii¥ I()r all I)11` 這種
        //    數字與符號堆出來的東西。純數字（價格、時間）本來也不需要翻譯。
        //    CJK 漢字在 Swift 也算 isLetter，所以中日韓文不受影響。
        let nonSpace = trimmed.filter { !$0.isWhitespace }
        let letters = nonSpace.filter { $0.isLetter }
        guard !nonSpace.isEmpty,
              Double(letters.count) / Double(nonSpace.count) >= 0.5 else { return false }

        // 3. 連續符號串
        var symbolRun = 0
        for s in scalars {
            let isSymbol = !CharacterSet.alphanumerics.contains(s)
                && !CharacterSet.whitespaces.contains(s)
            symbolRun = isSymbol ? symbolRun + 1 : 0
            if symbolRun >= 3 { return false }
        }

        // 4. 單字內部大小寫亂跳
        return !hasErraticCasing(trimmed)
    }

    /// 單字內部大小寫交錯 → 幾乎一定是辨識雜訊。
    ///
    /// 門檻設在「3 次以上切換」是為了保留正常的 camelCase 與品牌寫法：
    /// `iPhone`／`GenWorkspace` 是 2 次，要留；
    /// `IMI'K%ilik{Jii(I` 是 4 次，要擋。
    private static func hasErraticCasing(_ text: String) -> Bool {
        for token in text.split(separator: " ") {
            let letters = Array(token.filter { $0.isLetter })
            guard letters.count >= 4 else { continue }
            // 全大寫（LINE、QA 這類縮寫）或全小寫都正常
            if letters.allSatisfy({ $0.isUppercase }) || letters.allSatisfy({ $0.isLowercase }) {
                continue
            }
            var switches = 0
            for i in 1..<letters.count where letters[i].isUppercase != letters[i - 1].isUppercase {
                switches += 1
            }
            if switches >= 3 { return true }
        }
        return false
    }

    /// 快取鍵：忽略標點與大小寫的差異。
    /// OCR 在連續影格間常常只差一個標點（`QA testing` vs `QA testing.`），
    /// 用原字串當鍵會每幀都 miss，於是每幀都重送翻譯、每幀都換一次畫面。
    static func cacheKey(_ text: String) -> String {
        var key = ""
        for ch in text.lowercased() where ch.isLetter || ch.isNumber {
            key.append(ch)
        }
        return key.isEmpty ? text : key
    }
}

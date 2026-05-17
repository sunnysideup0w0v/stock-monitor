import Foundation

actor ClaudeAnalyzer {
    static let shared = ClaudeAnalyzer()
    private init() {}

    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func analyze(
        conditions: [ScreenerCondition],
        results: [StockUniverseItem],
        onToken: @MainActor @escaping (String) -> Void
    ) async throws {
        guard let apiKey = KeychainHelper.load(account: KeychainKey.anthropicApiKey), !apiKey.isEmpty else {
            throw AnalyzerError.noApiKey
        }

        let prompt = buildPrompt(conditions: conditions, results: results)
        let bodyData = try buildRequestBody(prompt: prompt)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw AnalyzerError.apiError(http.statusCode)
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]" else { break }
            if let text = parseTextDelta(from: json) {
                await onToken(text)
            }
        }
    }

    // MARK: - Prompt 구성

    private func buildPrompt(conditions: [ScreenerCondition], results: [StockUniverseItem]) -> String {
        var lines: [String] = [
            """
            당신은 한국 주식 시장 분석가입니다. 아래 스크리닝 결과를 바탕으로 투자 인사이트를 상세하게 분석해주세요.

            **출력 형식 규칙 (반드시 준수):**
            - 마크다운 문법만 사용 (HTML 태그 금지)
            - 섹션 제목은 ## 또는 ### 사용
            - 핵심 수치·종목명은 **볼드** 처리
            - 긍정 신호는 🟢, 부정/위험은 🔴, 주의사항은 ⚠️ 이모지 사용
            - 핵심 결론은 > 블록쿼트로 강조

            **주목 종목 분석 시 각 종목마다 아래 항목을 포함해주세요:**
            - 최근 주가·실적 동향
            - 최근 주요 이슈 1~2개 (공시, 신제품, 계약, 규제, 인사 등)
            - 투자 포인트 및 리스크
            """,
            "",
            "## 스크리닝 조건"
        ]
        for cond in conditions where cond.isEnabled {
            lines.append("- \(describeCondition(cond))")
        }

        lines.append("")
        let top = Array(results.prefix(20))
        lines.append("## 스크리닝 결과 (상위 \(top.count)개, 시가총액 내림차순)")
        for item in top {
            var parts = ["\(item.name)(\(item.symbol))", item.market]
            parts.append("현재가 \(item.close.formatted())원")
            parts.append("시총 \(item.marketCap / 100)억")
            if let per = item.per { parts.append("PER \(String(format: "%.1f", per))") }
            if let pbr = item.pbr { parts.append("PBR \(String(format: "%.2f", pbr))") }
            if let sector = item.sector { parts.append(sector) }
            lines.append("- " + parts.joined(separator: " | "))
        }

        lines.append("")
        lines.append("주목할 종목(최근 동향 + 주요 이슈 포함), 섹터 전반 동향, 종합 주의사항 순서로 분석해주세요.")
        return lines.joined(separator: "\n")
    }

    private func describeCondition(_ cond: ScreenerCondition) -> String {
        switch cond.type {
        case .priceRange:      return "현재가: \(rangeDesc(cond, unit: "원"))"
        case .volumeMin:       return "최소 거래량: \(cond.minValue.map { "\(Int($0).formatted())주" } ?? "—")"
        case .changeRateRange: return "등락률: \(rangeDesc(cond, unit: "%"))"
        case .perRange:        return "PER: \(rangeDesc(cond, unit: "배"))"
        case .pbrRange:        return "PBR: \(rangeDesc(cond, unit: "배"))"
        case .marketCapRange:  return "시가총액: \(rangeDesc(cond, unit: "억원"))"
        case .sectorFilter:    return "업종: \(cond.stringValue ?? "—")"
        case .marketFilter:    return "시장: \(cond.stringValue ?? "—")"
        case .instrumentType:  return "종목유형: \(cond.stringValue ?? "—")"
        }
    }

    private func rangeDesc(_ cond: ScreenerCondition, unit: String) -> String {
        switch (cond.minValue, cond.maxValue) {
        case let (min?, max?): return "\(fmtVal(min))\(unit) ~ \(fmtVal(max))\(unit)"
        case let (min?, nil):  return "\(fmtVal(min))\(unit) 이상"
        case let (nil, max?):  return "\(fmtVal(max))\(unit) 이하"
        default: return "—"
        }
    }

    private func fmtVal(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(v)) : String(format: "%.2f", v)
    }

    // MARK: - HTTP / SSE

    private func buildRequestBody(prompt: String) throws -> Data {
        let body: [String: Any] = [
            "model": "claude-sonnet-4-5",
            "max_tokens": 2048,
            "stream": true,
            "messages": [["role": "user", "content": prompt]]
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func parseTextDelta(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let delta = obj["delta"] as? [String: Any],
              let text  = delta["text"] as? String
        else { return nil }
        return text
    }

    // MARK: - Error

    enum AnalyzerError: LocalizedError {
        case noApiKey
        case apiError(Int)

        var errorDescription: String? {
            switch self {
            case .noApiKey:          return "Anthropic API 키가 설정되지 않았습니다"
            case .apiError(let c):   return "API 오류 (\(c)) — API 키와 네트워크를 확인하세요"
            }
        }
    }
}

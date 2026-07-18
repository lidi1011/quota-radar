import XCTest
@testable import QuotaRadar

final class ParserTests: XCTestCase {
    func testGLMStatusParserParsesRichStatusLine() {
        let status = GLMStatusParser.parse("32% · 3x · ⏱ 14:30 | 24% | 20/100")

        XCTAssertEqual(status.tokenPercent, 32)
        XCTAssertEqual(status.weeklyPercent, 24)
        XCTAssertEqual(status.resetText, "14:30")
        XCTAssertEqual(status.mcpText, "20/100")
        XCTAssertEqual(status.multiplier, "3x")
    }

    func testGLMStatusParserParsesLegacyStatusLine() {
        let status = GLMStatusParser.parse("32% (⌛️ 1:44) · 20/100")

        XCTAssertEqual(status.tokenPercent, 32)
        XCTAssertNil(status.weeklyPercent)
        XCTAssertEqual(status.resetText, "1:44")
        XCTAssertEqual(status.mcpText, "20/100")
    }

    func testCodexTokenParserExtractsNestedTokenCount() {
        let line = """
        {"type":"token_count","timestamp":"2026-07-05T00:00:00Z","usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200}}
        """

        let event = CodexTokenParser.parseLine(line, fileDate: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(event?.breakdown.uncachedInput, 700)
        XCTAssertEqual(event?.breakdown.cachedInput, 300)
        XCTAssertEqual(event?.breakdown.output, 200)
    }

    func testCodexTokenParserPrefersLastTokenUsageOverCumulativeTotals() {
        let line = """
        {"timestamp":"2026-07-05T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":900000,"output_tokens":500000},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200}}}}
        """

        let event = CodexTokenParser.parseLine(line, fileDate: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(event?.breakdown.uncachedInput, 700)
        XCTAssertEqual(event?.breakdown.cachedInput, 300)
        XCTAssertEqual(event?.breakdown.output, 200)
    }

    func testCodexTokenParserExtractsTotalUsageForDeltaMode() {
        let line = """
        {"timestamp":"2026-07-05T00:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"cached_input_tokens":900000,"output_tokens":500000},"last_token_usage":{"input_tokens":1000,"cached_input_tokens":300,"output_tokens":200}}}}
        """

        let event = CodexTokenParser.parseTotalLine(line, fileDate: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(event?.breakdown.uncachedInput, 100000)
        XCTAssertEqual(event?.breakdown.cachedInput, 900000)
        XCTAssertEqual(event?.breakdown.output, 500000)
        XCTAssertEqual(event?.breakdown.total, 1_500_000)
    }

    func testCodexRateLimitParserExtractsSessionRateLimits() {
        let line = """
        {"timestamp":"2026-07-05T00:00:00Z","type":"event_msg","payload":{"type":"token_count"},"rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1782531915},"secondary":{"used_percent":34.0,"window_minutes":10080,"resets_at":1782957624},"plan_type":"prolite"}}
        """

        let snapshot = CodexRateLimitParser.parseLine(line)

        XCTAssertEqual(snapshot?.primaryUsedPercent, 12)
        XCTAssertEqual(snapshot?.secondaryUsedPercent, 34)
        XCTAssertEqual(snapshot?.planType, "prolite")
        XCTAssertEqual(snapshot?.windows.first?.remainingPercent, 88)
        XCTAssertEqual(snapshot?.windows.first?.label, "5 小时")
        XCTAssertEqual(snapshot?.windows.last?.label, "7 天")
    }

    func testCodexAppServerRateLimitParserExtractsCodexLimit() {
        let result: [String: Any] = [
            "rateLimitsByLimitId": [
                "codex": [
                    "limitId": "codex",
                    "limitName": "Codex",
                    "primary": ["usedPercent": 24.0, "resetsAt": 1_782_531_915.0],
                    "secondary": ["usedPercent": 61.0, "resetsAt": 1_782_957_624.0]
                ]
            ]
        ]

        let snapshot = CodexAppServerRateLimitParser.parse(result)

        XCTAssertEqual(snapshot?.primaryUsedPercent, 24)
        XCTAssertEqual(snapshot?.secondaryUsedPercent, 61)
        XCTAssertEqual(snapshot?.windows.first?.remainingPercent, 76)
        XCTAssertEqual(snapshot?.windows.last?.remainingPercent, 39)
    }

    func testCodexAppServerRateLimitParserAcceptsSnakeCasePayload() {
        let result: [String: Any] = [
            "rate_limits_by_limit_id": [
                "codex": [
                    "limitId": "codex",
                    "primary": ["used_percent": 8.0, "resets_at": 1_782_531_915.0],
                    "secondary": ["used_percent": 25.0, "resets_at": 1_782_957_624.0]
                ]
            ]
        ]

        let snapshot = CodexAppServerRateLimitParser.parse(result)

        XCTAssertEqual(snapshot?.primaryUsedPercent, 8)
        XCTAssertEqual(snapshot?.secondaryUsedPercent, 25)
    }

    func testCodexRateLimitSnapshotDiscardsExpiredLogWindows() {
        let now = Date(timeIntervalSince1970: 1_782_600_000)
        let snapshot = CodexRateLimitSnapshot(
            primaryUsedPercent: 60,
            primaryResetsAt: now.addingTimeInterval(-60),
            secondaryUsedPercent: 25,
            secondaryResetsAt: now.addingTimeInterval(86_400),
            planType: "Codex"
        )

        let windows = snapshot.windows(discardExpiredBefore: now)

        XCTAssertEqual(windows.first?.id, "5h")
        XCTAssertEqual(windows.first?.usedPercent, 0)
        XCTAssertEqual(windows.first?.resetText, "未连接")
        XCTAssertEqual(windows.last?.id, "7d")
        XCTAssertEqual(windows.last?.usedPercent, 25)
        XCTAssertNotEqual(windows.last?.resetText, "未连接")
    }

    func testCodexResetCreditsParserExtractsIssuedAndExpiryDates() throws {
        let data = """
        {
          "available_count": 2,
          "credits": [
            {
              "id": "do-not-display-this-id",
              "granted_at": "2026-07-05T02:30:00.385078Z",
              "expires_at": "2026-07-12T02:30:00.385078Z"
            },
            {
              "createdAt": 1782531915,
              "expirationTime": 1782957624000
            }
          ]
        }
        """.data(using: .utf8)!

        let snapshot = try CodexResetCreditsParser.parse(data)

        XCTAssertEqual(snapshot.credits.count, 2)
        XCTAssertEqual(snapshot.usageCard.primaryValue, "2")
        XCTAssertNotNil(snapshot.credits.first?.issuedAt)
        XCTAssertNotNil(snapshot.credits.first?.expiresAt)
        XCTAssertTrue(snapshot.usageCard.note?.contains("发放") == true)
        XCTAssertFalse(snapshot.usageCard.note?.contains("未知") == true)
        XCTAssertFalse(snapshot.usageCard.note?.contains("do-not-display-this-id") == true)
    }

    func testCodexResetCreditsUnauthorizedReturnsSafeCard() async throws {
        let client = CodexResetCreditsClient {
            throw CodexResetCreditsError.unauthorized
        }

        let card = await client.usageCard()

        XCTAssertEqual(card.primaryValue, "--")
        XCTAssertEqual(card.note, "凭证失效或 Authorization header 不正确")
    }

    func testCompactTokenFormatting() {
        XCTAssertEqual(RadarFormatters.compactTokens(0), "0")
        XCTAssertEqual(RadarFormatters.compactTokens(1_500), "1.5K")
        XCTAssertEqual(RadarFormatters.compactTokens(2_300_000), "2.3M")
        XCTAssertEqual(RadarFormatters.compactTokens(1_460_700_000), "1.46B")
        XCTAssertEqual(RadarFormatters.compactTokens(1_000_000_000), "1B")
    }

    func testCountdownPercentFormattingKeepsOneDecimalWithoutChangingStandardPercent() {
        XCTAssertEqual(RadarFormatters.countdownPercent(99.53), "99.5%")
        XCTAssertEqual(RadarFormatters.percent(99.53), "100%")
    }

    func testResetFormatterUsesLocalTimeWithoutYear() {
        var components = DateComponents()
        components.calendar = Calendar.current
        components.year = 2026
        components.month = 7
        components.day = 5
        components.hour = 3
        components.minute = 5
        let date = components.date!

        XCTAssertEqual(RadarFormatters.resetDateTime(date), "07-05 03:05")
    }

    func testSubscriptionRemainingFormatting() throws {
        let now = try dateUTC8(year: 2026, month: 7, day: 6, hour: 10, minute: 0)
        let future = try dateUTC8(year: 2026, month: 7, day: 9, hour: 1, minute: 0)
        let today = try dateUTC8(year: 2026, month: 7, day: 6, hour: 23, minute: 0)
        let expired = try dateUTC8(year: 2026, month: 7, day: 4, hour: 23, minute: 0)

        XCTAssertEqual(RadarFormatters.subscriptionRemainingText(future, now: now), "剩余 3 天")
        XCTAssertEqual(RadarFormatters.subscriptionRemainingText(today, now: now), "今天到期")
        XCTAssertEqual(RadarFormatters.subscriptionRemainingText(expired, now: now), "已过期 2 天")
        XCTAssertEqual(RadarFormatters.subscriptionDate(future), "2026-07-09")
    }

    func testSubscriptionInfoUnavailableCard() {
        let card = SubscriptionInfo.unavailable.usageCard()

        XCTAssertEqual(card.id, .subscriptionExpiry)
        XCTAssertEqual(card.primaryValue, "未设置")
        XCTAssertEqual(card.trailingValue, "")
        XCTAssertEqual(card.note, "未从接口读取到订阅到期时间")
    }

    func testMonthlySubscriptionRuleUsesCurrentMonthWhenUpcoming() throws {
        let now = try dateUTC8(year: 2026, month: 7, day: 6, hour: 10, minute: 0)
        let next = ManualSubscriptionRule.monthly(day: 15).nextDate(now: now)

        XCTAssertEqual(RadarFormatters.subscriptionDate(next), "2026-07-15")
        XCTAssertEqual(RadarFormatters.subscriptionRemainingText(next, now: now), "剩余 9 天")
    }

    func testMonthlySubscriptionRuleUsesNextMonthAfterRenewalDay() throws {
        let now = try dateUTC8(year: 2026, month: 7, day: 16, hour: 10, minute: 0)
        let next = ManualSubscriptionRule.monthly(day: 15).nextDate(now: now)

        XCTAssertEqual(RadarFormatters.subscriptionDate(next), "2026-08-15")
    }

    func testMonthlySubscriptionRuleClampsToMonthEnd() throws {
        let now = try dateUTC8(year: 2026, month: 2, day: 1, hour: 10, minute: 0)
        let next = ManualSubscriptionRule.monthly(day: 31).nextDate(now: now)

        XCTAssertEqual(RadarFormatters.subscriptionDate(next), "2026-02-28")
    }

    func testTodayStartUsesLocalTimeZone() throws {
        var input = DateComponents()
        input.calendar = Calendar.current
        input.year = 2026
        input.month = 7
        input.day = 5
        input.hour = 15
        input.minute = 30
        let date = try XCTUnwrap(input.date)

        let start = RadarFormatters.localCalendar.startOfDay(for: date)
        let components = RadarFormatters.localCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: start)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 7)
        XCTAssertEqual(components.day, 5)
        XCTAssertEqual(components.hour, 0)
        XCTAssertEqual(components.minute, 0)
    }

    func testCodexProgressMarkersUseCodexUSubscriptionBand() {
        let progress = PlanProgress.codex(value: 27.62)

        XCTAssertEqual(progress.markers.map(\.label), ["Plus", "Pro100", "Pro200"])
        XCTAssertEqual(progress.markers[0].position, 0.028, accuracy: 0.001)
        XCTAssertEqual(progress.markers[1].position, 0.14, accuracy: 0.001)
        XCTAssertEqual(progress.markers[2].position, 0.28, accuracy: 0.001)
        XCTAssertEqual(progress.progress, 0.038668, accuracy: 0.001)
    }

    func testGLMPlatformNormalizesZhipuAnthropicBaseURL() {
        let platform = GLMPlatform.detect(from: "https://open.bigmodel.cn/api/anthropic")

        XCTAssertEqual(platform, .zhipu)
        XCTAssertEqual(platform?.normalizedBaseURL("https://open.bigmodel.cn/api/anthropic"), "https://open.bigmodel.cn/api")
    }

    func testGLMMultiplierUsesPeakRateForPremiumModel() throws {
        let date = try dateUTC8(year: 2026, month: 7, day: 5, hour: 15, minute: 0)

        let multiplier = GLMMultiplierCalculator.calculate(date: date, modelID: "glm-5.2")

        XCTAssertEqual(multiplier, 3.0)
        XCTAssertEqual(GLMMultiplierCalculator.format(multiplier), "3x")
    }

    func testGLMMultiplierUsesPromoOffPeakRateForPremiumModel() throws {
        let date = try dateUTC8(year: 2026, month: 7, day: 5, hour: 10, minute: 0)

        let multiplier = GLMMultiplierCalculator.calculate(date: date, modelID: "glm-5.2")
        let info = GLMMultiplierCalculator.currentInfo(date: date, modelID: "glm-5.2")

        XCTAssertEqual(multiplier, 1.0)
        XCTAssertEqual(info.displayValue, "1x")
        XCTAssertEqual(info.periodLabel, "促销")
    }

    func testGLMMultiplierIgnoresNonPremiumModel() throws {
        let date = try dateUTC8(year: 2026, month: 7, day: 5, hour: 15, minute: 0)

        let multiplier = GLMMultiplierCalculator.calculate(date: date, modelID: "glm-4")

        XCTAssertEqual(multiplier, 1.0)
    }

    func testSubscriptionParserAcceptsSnakeCaseAndISODate() throws {
        let data = """
        {
          "subscription": {
            "expires_at": "2026-08-06T00:00:00Z",
            "plan_name": "Codex Pro"
          }
        }
        """.data(using: .utf8)!

        let info = try XCTUnwrap(SubscriptionInfoParser.parse(data: data))

        XCTAssertEqual(info.planName, "Codex Pro")
        XCTAssertEqual(info.source, .automatic)
        XCTAssertEqual(info.expiresAt?.timeIntervalSince1970, 1_785_974_400)
    }

    func testSubscriptionParserAcceptsCamelCaseAndMillisecondTimestamp() throws {
        let object: [String: Any] = [
            "account": [
                "currentPeriodEnd": 1_785_974_400_000,
                "planName": "GLM Coding"
            ]
        ]

        let info = try XCTUnwrap(SubscriptionInfoParser.parse(object))

        XCTAssertEqual(info.planName, "GLM Coding")
        XCTAssertEqual(info.expiresAt?.timeIntervalSince1970, 1_785_974_400)
    }

    func testSubscriptionParserAcceptsRenewalTimestampSeconds() throws {
        let object: [String: Any] = [
            "data": [
                "renewsAt": 1_785_974_400
            ]
        ]

        let info = try XCTUnwrap(SubscriptionInfoParser.parse(object))

        XCTAssertNil(info.expiresAt)
        XCTAssertEqual(info.renewsAt?.timeIntervalSince1970, 1_785_974_400)
    }

    func testProviderPreferencesDecodesLegacyPayloadAsVisible() throws {
        let data = """
        {
          "ringPrimaryHex": "#1E88FF",
          "ringSecondaryHex": "#8B5CF6",
          "cardAccentHex": "#2563EB",
          "visibleCards": ["today", "sevenDays"]
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(ProviderPreferences.self, from: data)

        XCTAssertTrue(preferences.isVisible)
        XCTAssertEqual(preferences.visibleCards, [.today, .sevenDays])
    }

    func testCodexPreferencesMigrationAddsResetCreditsCard() {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        ProviderPreferences(
            ringPrimaryHex: "#1E88FF",
            ringSecondaryHex: "#8B5CF6",
            cardAccentHex: "#2563EB",
            visibleCards: [.today]
        ).save(provider: .codex, defaults: defaults)

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.isVisible(.resetCredits, for: .codex))
    }

    func testPreferencesMigrationAddsSubscriptionExpiryCard() {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        ProviderPreferences(
            ringPrimaryHex: "#14B8A6",
            ringSecondaryHex: "#F97316",
            cardAccentHex: "#10B981",
            visibleCards: [.tokenUsage]
        ).save(provider: .glm, defaults: defaults)

        let settings = AppSettings(defaults: defaults)

        XCTAssertTrue(settings.isVisible(.subscriptionExpiry, for: .glm))
    }

    func testLegacyManualSubscriptionDateMigratesToMonthlyRule() throws {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(try dateUTC8(year: 2027, month: 7, day: 15, hour: 0, minute: 0), forKey: "subscriptionExpiry.glm.manual")

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.glmManualSubscriptionRule, .monthly(day: 15))
        XCTAssertNil(defaults.object(forKey: "subscriptionExpiry.glm.manual"))
    }

    func testCodexRemoteSubscriptionLookupDefaultsDisabled() {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertFalse(settings.codexRemoteSubscriptionLookupEnabled)
        settings.codexRemoteSubscriptionLookupEnabled = true
        XCTAssertTrue(AppSettings(defaults: defaults).codexRemoteSubscriptionLookupEnabled)
    }

    func testProviderLayoutModeDefaultsVerticalAndPersists() {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.providerLayoutMode, .vertical)
        settings.providerLayoutMode = .horizontal
        XCTAssertEqual(AppSettings(defaults: defaults).providerLayoutMode, .horizontal)
    }

    func testCodexQuotaRingModeDefaultsToSevenDayAndPersistsDualWindowChoice() {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.codexQuotaRingMode, .sevenDay)
        settings.codexQuotaRingMode = .fiveHourAndSevenDay
        XCTAssertEqual(AppSettings(defaults: defaults).codexQuotaRingMode, .fiveHourAndSevenDay)
    }

    func testCodexQuotaRingModeKeepsLegacyDualWindowsUnchanged() {
        let windows = [
            UsageWindow(id: "5h", label: "5 小时", remainingPercent: 80, usedPercent: 20, resetText: "稍后"),
            UsageWindow(id: "7d", label: "7 天", remainingPercent: 60, usedPercent: 40, resetText: "下周")
        ]

        XCTAssertEqual(CodexQuotaRingMode.fiveHourAndSevenDay.windows(from: windows), windows)
    }

    func testCodexSevenDayModeUsesSolePrimaryWindowAndAddsCountdownRing() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let nextReset = now.addingTimeInterval(6 * 24 * 60 * 60)
        let result: [String: Any] = [
            "rateLimits": [
                "limitName": "Codex",
                "primary": ["usedPercent": 25.0, "resetsAt": nextReset.timeIntervalSince1970]
            ]
        ]
        let snapshot = try XCTUnwrap(CodexAppServerRateLimitParser.parse(result))

        let windows = CodexQuotaRingMode.sevenDay.windows(from: snapshot.windows, now: now)

        XCTAssertEqual(windows.map(\.id), ["7d", "7dCountdown"])
        XCTAssertEqual(windows[0].label, "7 天")
        XCTAssertEqual(windows[0].remainingPercent, 75)
        XCTAssertEqual(windows[0].resetsAt, nextReset)
        XCTAssertNotEqual(windows[0].resetText, "未知")
        XCTAssertEqual(windows[0].preferredRingRole, .secondary)
        XCTAssertFalse(windows[0].isCountdown)
        XCTAssertEqual(windows[1].label, "倒计时")
        XCTAssertEqual(windows[1].remainingPercent, 600 / 7, accuracy: 0.001)
        XCTAssertEqual(windows[1].resetText, "6天0小时0分")
        XCTAssertEqual(windows[1].preferredRingRole, .primary)
        XCTAssertTrue(windows[1].isCountdown)
    }

    func testCodexSevenDayModePrefersRealSecondaryWindowWhenBothPeriodsExist() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let primaryReset = now.addingTimeInterval(2 * 60 * 60)
        let secondaryReset = now.addingTimeInterval(5 * 24 * 60 * 60)
        let snapshot = CodexRateLimitSnapshot(
            primaryUsedPercent: 20,
            primaryResetsAt: primaryReset,
            secondaryUsedPercent: 40,
            secondaryResetsAt: secondaryReset,
            planType: "Codex"
        )

        let windows = CodexQuotaRingMode.sevenDay.windows(from: snapshot.windows, now: now)

        XCTAssertEqual(windows[0].remainingPercent, 60)
        XCTAssertEqual(windows[0].resetsAt, secondaryReset)
        XCTAssertEqual(windows[1].remainingPercent, 500 / 7, accuracy: 0.001)
        XCTAssertEqual(windows[1].resetText, "5天0小时0分")
    }

    func testCodexSubscriptionReaderSkipsBackendWhenRemoteLookupDisabled() async {
        let calls = AsyncCounter()
        let reader = CodexSubscriptionReader(
            codexRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            allowRemoteBackendLookup: false,
            appServerReader: { nil },
            backendFetcher: {
                await calls.increment()
                return SubscriptionInfo(expiresAt: Date(), renewsAt: nil, planName: "Remote", source: .automatic)
            }
        )

        let info = await reader.subscriptionInfo(force: true)

        XCTAssertNil(info)
        let callCount = await calls.value
        XCTAssertEqual(callCount, 0)
    }

    func testCodexSubscriptionReaderCachesBackendResult() async throws {
        let expiry = try dateUTC8(year: 2026, month: 8, day: 6, hour: 0, minute: 0)
        let automatic = SubscriptionInfo(expiresAt: expiry, renewsAt: nil, planName: "Codex Pro", source: .automatic)
        let calls = AsyncCounter()
        let reader = CodexSubscriptionReader(
            codexRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            allowRemoteBackendLookup: true,
            cache: SubscriptionInfoCache(),
            cacheTTLSeconds: 3_600,
            appServerReader: { nil },
            backendFetcher: {
                await calls.increment()
                return automatic
            }
        )

        let first = await reader.subscriptionInfo()
        let second = await reader.subscriptionInfo()
        let forced = await reader.subscriptionInfo(force: true)

        XCTAssertEqual(first, automatic)
        XCTAssertEqual(second, automatic)
        XCTAssertEqual(forced, automatic)
        let callCount = await calls.value
        XCTAssertEqual(callCount, 2)
    }

    func testCodexSubscriptionReaderCachesMissingBackendResult() async {
        let calls = AsyncCounter()
        let reader = CodexSubscriptionReader(
            codexRoot: URL(fileURLWithPath: NSTemporaryDirectory()),
            allowRemoteBackendLookup: true,
            cache: SubscriptionInfoCache(),
            cacheTTLSeconds: 3_600,
            appServerReader: { nil },
            backendFetcher: {
                await calls.increment()
                return nil
            }
        )

        let first = await reader.subscriptionInfo()
        let second = await reader.subscriptionInfo()

        XCTAssertNil(first)
        XCTAssertNil(second)
        let callCount = await calls.value
        XCTAssertEqual(callCount, 1)
    }

    func testGLMForceRefreshBypassesCachedStats() async throws {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.glmAuthToken = "test-token"
        settings.glmBaseURL = "https://open.bigmodel.cn/api/anthropic"

        let calls = AsyncCounter()
        let client = GLMQuotaClient { _, _ in
            await calls.increment()
            let count = await calls.value
            return GLMUsageStats(
                platform: .zhipu,
                tokenUsage: GLMQuotaUsage(used: count, limit: 100, percentage: count, timeWindow: "5h", resetAt: nil),
                weeklyUsage: nil,
                mcpUsage: nil
            )
        }
        let provider = GLMProvider(settings: settings, cache: GLMQuotaCache(), client: client)

        let first = try await provider.snapshot(force: false)
        let cached = try await provider.snapshot(force: false)
        let forced = try await provider.snapshot(force: true)

        XCTAssertEqual(first.cards.first?.primaryValue, "1%")
        XCTAssertEqual(cached.cards.first?.primaryValue, "1%")
        XCTAssertEqual(forced.cards.first?.primaryValue, "2%")
        let callCount = await calls.value
        XCTAssertEqual(callCount, 2)
    }

    func testGLMProviderUsesAutomaticSubscriptionBeforeManualFallback() async throws {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.glmAuthToken = "test-token"
        settings.glmManualSubscriptionRule = .monthly(day: 10)
        let automaticExpiry = try dateUTC8(year: 2026, month: 8, day: 6, hour: 0, minute: 0)
        let client = GLMQuotaClient { _, _ in
            GLMUsageStats(
                platform: .zhipu,
                tokenUsage: nil,
                weeklyUsage: nil,
                mcpUsage: nil,
                subscriptionInfo: SubscriptionInfo(expiresAt: automaticExpiry, renewsAt: nil, planName: "GLM Pro", source: .automatic)
            )
        }

        let snapshot = try await GLMProvider(settings: settings, cache: GLMQuotaCache(), client: client).snapshot(force: true)
        let card = try XCTUnwrap(snapshot.cards.first { $0.id == .subscriptionExpiry })

        XCTAssertEqual(card.trailingValue, "2026-08-06")
        XCTAssertEqual(card.note, "自动读取 · GLM Pro")
    }

    func testGLMProviderUsesManualSubscriptionFallback() async throws {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.glmAuthToken = "test-token"
        settings.glmManualSubscriptionRule = .fixedDate(try dateUTC8(year: 2026, month: 7, day: 10, hour: 0, minute: 0))
        let client = GLMQuotaClient { _, _ in
            GLMUsageStats(platform: .zhipu, tokenUsage: nil, weeklyUsage: nil, mcpUsage: nil)
        }

        let snapshot = try await GLMProvider(settings: settings, cache: GLMQuotaCache(), client: client).snapshot(force: true)
        let card = try XCTUnwrap(snapshot.cards.first { $0.id == .subscriptionExpiry })

        XCTAssertEqual(card.trailingValue, "2026-07-10")
        XCTAssertEqual(card.note, "手动设置 · 2026-07-10")
    }

    func testGLMProviderShowsUnsetSubscriptionWithoutAutomaticOrManualDate() async throws {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.glmAuthToken = "test-token"
        let client = GLMQuotaClient { _, _ in
            GLMUsageStats(platform: .zhipu, tokenUsage: nil, weeklyUsage: nil, mcpUsage: nil)
        }

        let snapshot = try await GLMProvider(settings: settings, cache: GLMQuotaCache(), client: client).snapshot(force: true)
        let card = try XCTUnwrap(snapshot.cards.first { $0.id == .subscriptionExpiry })

        XCTAssertEqual(card.primaryValue, "未设置")
        XCTAssertEqual(card.note, "未从接口读取到订阅到期时间")
    }

    func testGLMProviderUsesSeparateMCPMeterValue() async throws {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.glmAuthToken = "test-token"
        let client = GLMQuotaClient { _, _ in
            GLMUsageStats(
                platform: .zhipu,
                tokenUsage: nil,
                weeklyUsage: nil,
                mcpUsage: GLMQuotaUsage(used: 129, limit: 1000, percentage: 12, timeWindow: "30d", resetAt: nil)
            )
        }

        let snapshot = try await GLMProvider(settings: settings, cache: GLMQuotaCache(), client: client).snapshot(force: true)
        let card = try XCTUnwrap(snapshot.cards.first { $0.id == .mcpUsage })

        XCTAssertEqual(card.primaryValue, "12%")
        XCTAssertEqual(card.note, "129/1000")
        XCTAssertEqual(card.meterValue ?? 0, 0.785, accuracy: 0.001)
    }

    func testGLMProviderSeparatesUsedPercentFromRemainingQuotaMeters() async throws {
        let suiteName = "QuotaRadarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        settings.glmAuthToken = "test-token"
        let client = GLMQuotaClient { _, _ in
            GLMUsageStats(
                platform: .zhipu,
                tokenUsage: GLMQuotaUsage(used: 0, limit: 100, percentage: 0, timeWindow: "5h", resetAt: nil),
                weeklyUsage: GLMQuotaUsage(used: 3, limit: 100, percentage: 3, timeWindow: "7d", resetAt: nil),
                mcpUsage: nil
            )
        }

        let snapshot = try await GLMProvider(
            settings: settings,
            cache: GLMQuotaCache(),
            client: client
        ).snapshot(force: true)
        let tokenCard = try XCTUnwrap(snapshot.cards.first { $0.id == .tokenUsage })
        let weeklyCard = try XCTUnwrap(snapshot.cards.first { $0.id == .weeklyQuota })

        XCTAssertEqual(tokenCard.title, "5 小时已使用")
        XCTAssertEqual(tokenCard.primaryValue, "0%")
        XCTAssertEqual(tokenCard.meterValue ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(weeklyCard.title, "7 天已使用")
        XCTAssertEqual(weeklyCard.primaryValue, "3%")
        XCTAssertEqual(weeklyCard.meterValue ?? -1, 0.97, accuracy: 0.001)
    }

    func testCommandRunnerTerminatesTimedOutProcess() {
        XCTAssertThrowsError(try CommandRunner().run("/bin/sleep", arguments: ["2"], timeout: 0.1)) { error in
            XCTAssertTrue(error is CommandRunnerError)
        }
    }

}

private func dateUTC8(year: Int, month: Int, day: Int, hour: Int, minute: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    var components = DateComponents()
    components.calendar = calendar
    components.timeZone = calendar.timeZone
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return try XCTUnwrap(components.date)
}

private actor AsyncCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

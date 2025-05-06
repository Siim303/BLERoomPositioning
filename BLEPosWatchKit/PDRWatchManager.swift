//
//  PDRWatchManager.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 05.05.2025.
//
//  PDRWatchManager.swift            (also in *WatchKit Extension* target)
import CoreMotion
import WatchConnectivity

final class PDRWatchManager: NSObject, WCSessionDelegate {

    private let pedometer = CMPedometer()
    private let motion    = CMMotionManager()
    private var lastStep  = 0
    private var heading   = 0.0          // degrees (true north)
    private let wc = WCSession.default

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        wc.delegate = self
        wc.activate()
    }

    // MARK: – public control
    func start() {
        startHeading()
        startSteps()
    }
    func stop() {
        motion.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
    }

    // MARK: – heading
    private func startHeading() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.startDeviceMotionUpdates(using: .xTrueNorthZVertical,
                                        to: .main) { [weak self] dm, _ in
            self?.heading = dm?.heading ?? 0
        }
    }

    // MARK: – steps
    private func startSteps() {
        guard CMPedometer.isStepCountingAvailable() else { return }
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let self, let data else { return }

            let delta = data.numberOfSteps.intValue - self.lastStep
            guard delta > 0 else { return }
            self.lastStep = data.numberOfSteps.intValue

            // simple constant step length (metres)
            let L  = 0.70
            let θ  = self.heading * .pi / 180
            let dx = cos(θ) * L * Double(delta)
            let dy = sin(θ) * L * Double(delta)

            if self.wc.isReachable {
                self.wc.sendMessage(["dx": dx, "dy": dy, "steps": delta],
                                    replyHandler: nil, errorHandler: nil)
            }
        }
    }

    // MARK: – WCSessionDelegate placeholders
    func session(_: WCSession, activationDidCompleteWith _: WCSessionActivationState, error _: Error?) {}
    func sessionReachabilityDidChange(_: WCSession) {}
    //func sessionDidBecomeInactive(_: WCSession) {}
    //func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}

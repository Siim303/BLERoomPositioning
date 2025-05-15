//
//  PDRManager.swift
//  BLERoomPositioning
//
//  Created by Siim Turban on 05.05.2025.
//

import Combine
import CoreMotion
import SwiftUI
import WatchConnectivity
import os.log

struct PDRUpdate {
    let position: CGPoint
    let steps: Int
}

/// Pedestrian Dead Reckoning manager — step driven, heading aware
final class PDRManager: NSObject, ObservableObject, WCSessionDelegate {
    func sessionDidBecomeInactive(_ session: WCSession) {
        log.info("WCSession became inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        log.info("WCSession re‑activated")
    }

    enum Source { case phone, watch }
    private(set) var source: Source = .phone  // current sensor origin

    // MARK: – Public state
    @Published private(set) var headingDeg: Double = 0  // 0 = north, clockwise
    //  Published debug metrics
    @Published private(set) var stepCount: Int = 0
    @Published private(set) var stepLength: Double = 0  // last est. metres

    private var lastStepCountForFusion: Int = 0

    private var lastZ: Double = 0
    private var lastStepTimestamp: TimeInterval = 0

    // MARK: – Tuning
    var fixedStepLength: Double = 1.4 // m – quick start; can swap in dynamic value
    var zeroHeadingOffset: Double = 0  // user‑triggered calibration (deg)

    // MARK: – Private stuff
    private let motion = CMMotionManager()
    private let pedometer = CMPedometer()
    private var lastStepCount: Int = 0
    private let q = OperationQueue()
    private var rawHeading: Double = 0

    private let log = Logger(subsystem: "PDR", category: "core")

    // --- WatchConnectivity ---
    private let wc = WCSession.default

    override init() {
        super.init()
        log.info(
            "WcSession.isSupported: \(WCSession.isSupported().description)")
        log.info(
            "WC paired: \(self.wc.isPaired), WC app installed: \(self.wc.isWatchAppInstalled)"
        )
        if WCSession.isSupported(), wc.isPaired, wc.isWatchAppInstalled {
            log.info("Setting up WatchConnectivity")
            wc.delegate = self
            wc.activate()
            source = .watch/// we’ll wait for vectors
        }
    }

    // MARK: – Lifecycle
    func start() {
        switch source {
        case .phone:
            startHeadingUpdates()
            //startStepUpdates()
            startAccelerometerUpdates()
            calibrateHeading()
        case .watch:
            /// Nothing local; just integrate incoming vectors
            break
        }
    }

    func stop() {
        pedometer.stopUpdates()
        motion.stopDeviceMotionUpdates()
    }

    // MARK: – receive step vectors from the Watch
    func session(_ session: WCSession, didReceiveMessage msg: [String: Any]) {
        guard
            //let dx = msg["dx"] as? Double,
            //let dy = msg["dy"] as? Double,
            let steps = msg["steps"] as? Int
        else { return }

        DispatchQueue.main.async {
            //self.position.x += dx
            //self.position.y += dy
            self.stepCount += steps
        }
    }

    func session(
        _: WCSession, activationDidCompleteWith: WCSessionActivationState,
        error: Error?
    ) {}

    // Called from the “Calibrate” button so map north == device forward
    func calibrateHeading() {
        if zeroHeadingOffset == 0.0 {
            zeroHeadingOffset = 7.0001 // 103.0
        } else {
            zeroHeadingOffset = rawHeading
        }
        log.info("New zeroHeadingOffset = \(self.zeroHeadingOffset)")
    }

    // MARK: – Heading
    private func startHeadingUpdates() {
        guard motion.isDeviceMotionAvailable else {
            log.error("Device motion not available")
            return
        }

        /// .xTrueNorthZVertical gives yaw == compass‑true‑north on a flat device.
        /// You get stable degrees in `deviceMotion.heading` (iOS 17+)
        /// On older versions you need to compute yaw manually.
        motion.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical,
            to: q
        ) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let raw = dm.heading  // degrees
            DispatchQueue.main.async {
                self.rawHeading = raw
                self.headingDeg = raw - self.zeroHeadingOffset
            }

        }

        log.info("Heading updates started.")

    }

    /* TODO: To delete
    // MARK: – Step detection + position update
    private func startStepUpdates() {

        log.debug("Starting CMPedometer updates…")

        pedometer.queryPedometerData(
            from: Date(timeIntervalSinceNow: -60),
            to: Date()
        ) { data, error in
            log.debug("Last‑minute steps = \(data?.numberOfSteps ?? 0)")
        }

        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            //print("🔥 pedometer callback")
            if let error {  // ❶ report permission / HW issues
                log.error("Pedometer error: \(error.localizedDescription)")
            }
            guard let self, let data else {
                log.error("return from guard")
                return
            }
            //print("before seting lastStepCount")
            let stepsNow = data.numberOfSteps.intValue
            log.debug("StepsNow: \(String(describing:stepsNow))")
            let deltaSteps = stepsNow - self.lastStepCount
            self.lastStepCount = stepsNow

            // Optional: dynamic step length if distance is supplied
            var stepLength = self.fixedStepLength
            if let dist = data.distance?.doubleValue, deltaSteps > 0 {
                stepLength = dist / Double(deltaSteps)
            }

            guard deltaSteps > 0 else {
                log.error("deltaSteps <= 0")
                return
            }

            log.debug("Before dispatch.")

            DispatchQueue.main.async {
                self.stepCount = stepsNow
                self.stepLength = stepLength
                /*if deltaSteps > 0 {
                    self.advance(by: deltaSteps, stepLength: stepLength)
                    log.debug("Δ\(deltaSteps) steps → pos \(self.position)")
                }*/
                log.debug("Δ\(deltaSteps) steps → pos")
                //self.advance(by: deltaSteps, stepLength: stepLength)
            }
        }

    }
*/
    private func startAccelerometerUpdates() {
        guard motion.isAccelerometerAvailable else {
            log.error("Accelerometer not available")
            return
        }

        motion.accelerometerUpdateInterval = 1.0 / 10.0  // 50 Hz

        motion.startAccelerometerUpdates(to: q) { [weak self] data, _ in
            guard let self, let data = data else { return }

            let z = data.acceleration.z
            //log.debug("New accelerometer data: \(z)")
            self.detectStepFromZ(z)
        }
        log.info("Accelerometer updates started.")
    }

    private func detectStepFromZ(_ z: Double) {
        let now = Date().timeIntervalSince1970
        let deltaZ = z - lastZ

        /// Tune this threshold and debounce time to change step logging
        let spikeThreshold = 0.4
        let minTimeBetweenSteps = 0.4  // seconds

        if deltaZ > spikeThreshold,
            now - lastStepTimestamp > minTimeBetweenSteps
        {
            DispatchQueue.main.async {
                self.stepCount += 1
                self.stepLength = self.fixedStepLength  // Potentially could be made dynamic
            }
            lastStepTimestamp = now
            //log.debug("Step detected: ΔZ = \(deltaZ), stepCount = \(self.stepCount)")
        }

        lastZ = z
    }

    func computeStepDelta(from lastStepCount: Int) -> CGPoint? {
        let newSteps = stepCount - lastStepCount
        guard newSteps > 0 else { return nil }

        let θ = (headingDeg - 35) * .pi / 180.0 // -66
        let dx = cos(θ) * stepLength * Double(newSteps)
        let dy = sin(θ) * stepLength * Double(newSteps)

        return CGPoint(x: dx, y: dy)
    }
}

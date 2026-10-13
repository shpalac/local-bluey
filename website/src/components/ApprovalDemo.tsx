import { useState } from 'react';
import { AnimatePresence, MotionConfig, motion } from 'motion/react';

export default function ApprovalDemo() {
  const [approved, setApproved] = useState(false);

  return (
    <MotionConfig reducedMotion="user" transition={{ type: 'spring', stiffness: 300, damping: 24 }}>
      <div className="approval-demo">
        <div className="approval-demo-top"><span className="demo-traffic">● ● ●</span><span>BLUEY / ACTION REVIEW</span></div>
        <div className="approval-demo-content">
          <div className="demo-bubble">✳</div>
          <div>
            <span className="demo-kicker">ILLUSTRATIVE DEMO</span>
            <h3>One quick check.</h3>
            <p>Bluey wants to open an app on your Mac. You decide what happens next.</p>
          </div>
        </div>
        <div className="demo-status" role="status" aria-live="polite">
          <span className={approved ? 'demo-status-dot is-approved' : 'demo-status-dot'}></span>
          <AnimatePresence mode="wait" initial={false}>
            <motion.span key={String(approved)} initial={{ opacity: 0, y: 5 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -5 }}>
              {approved ? 'Approved — demo only' : 'Awaiting your approval'}
            </motion.span>
          </AnimatePresence>
        </div>
        <div className="demo-buttons">
          <motion.button
            type="button"
            whileHover={{ scale: 1.03 }}
            whileTap={{ scale: 0.97 }}
            onClick={() => setApproved((value) => !value)}
            aria-label={approved ? 'Reset demo' : 'Approve demo action'}
          >
            {approved ? '↶ Reset demo' : '✓ Approve demo action'}
          </motion.button>
          <span>NOT CONNECTED TO YOUR MAC</span>
        </div>
      </div>
    </MotionConfig>
  );
}

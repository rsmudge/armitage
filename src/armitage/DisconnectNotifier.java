package armitage;

import java.util.*;

/* an object to track listeners for disconnects... */
public class DisconnectNotifier {
	public interface DisconnectListener {
		public void disconnected(String reason);
	}

	protected List listeners    = new LinkedList();
	protected boolean connected = true;

	public void addDisconnectListener(DisconnectListener l) {
		synchronized (listeners) {
			listeners.add(l);
		}
	}

	public void fireDisconnectEvent(final String reason) {
		new Thread(new Runnable() {
			public void run() {
				synchronized (listeners) {
					if (!connected)
						return;

					Iterator i = listeners.iterator();
					while (i.hasNext()) {
						DisconnectListener l = (DisconnectListener)i.next();
						l.disconnected(reason);
					}

					connected = false;
				}
			}
		}).start();
	}
}

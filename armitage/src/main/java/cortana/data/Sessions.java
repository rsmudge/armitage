package cortana.data;

import cortana.core.*;

import sleep.runtime.*;

import java.util.*;

import msf.*;

public class Sessions extends ManagedData {
	protected RpcConnection  client;
	protected EventManager   manager;
	protected Hosts          hosts;
	protected Set            nonsync = new HashSet();
	protected Map            sessions = new HashMap();

	public Sessions(Hosts hosts, RpcConnection client, EventManager manager) {
		this.client  = client;
		this.manager = manager;
		this.hosts   = hosts;
	}

	public Map getSession(String id) {
		return (Map)sessions.get(id);
	}

	public Map getSessions() {
		return sessions;
	}

	public Scalar getScalar() {
		if (cache == null)
			cache = FilterManager.convertAll(getSessions());

		return cache;
	}

	/* a shortcut to fire session events */
	protected void fireSessionEvents(String name, Iterator sids, Map argumentData) {
		if (initial)
			return;

		while (sids.hasNext()) {
			String sid = sids.next() + "";

			Stack args = new Stack();
			args.push(FilterManager.convertAll((Map)argumentData.get(sid)));
			args.push(SleepUtils.getScalar(sid));

			manager.fireEventAsync(name, args);
		}
	}

	private static final void fixIPv6(Map data, String key) {
		if (!data.containsKey(key))
			return;

		/* strip scopeid out of address--so it doesn't mess up how we
		   associate session information with host */
		String value = data.get(key) + "";
		if (value.contains("%") && value.contains(":") && !value.startsWith("%")) {
			value = value.split("%")[0];
			data.put(key, value);
		}
	}

	public void processSessions(Map results) {
		if (hosts.isInitial())
			return;

		/* invalidate the cache */
		cache = null;
		hosts.cache = null;

		sessions = results;

		Set before = new HashSet();
		Set after  = new HashSet();
		Map dataz  = new HashMap();

		Set syncz  = new HashSet(); /* track sessions that are now synced */

		/* clear all of the sessions */
		Iterator j = hosts.getHosts().values().iterator();
		while (j.hasNext()) {
			Host host = (Host)j.next();
			before.addAll(host.getSessions().keySet());
			dataz.putAll(host.getSessions());
			host.getSessions().clear();
		}

		/* add all of these sessions to our after set*/
		after.addAll(results.keySet());
		dataz.putAll(results);

		/* add sessions to the appropriate hosts*/
		Iterator k = results.entrySet().iterator();
		while (k.hasNext()) {
			Map.Entry temp    = (Map.Entry)k.next();
			String    sid     = temp.getKey() + "";
			Map       session = (Map)temp.getValue();

			/* fix a few things */
			fixIPv6(session, "session_host");
			fixIPv6(session, "target_host");
			fixIPv6(session, "tunnel_peer");

			/* extract the address */
			String address = session.get("session_host") + "";

			if ("".equals(address)) {
				address = session.get("target_host") + "";
			}

			if ("".equals(address)) {
				address = ((String)session.get("tunnel_peer")).split(":")[0];
			}

			/* OK, now move on with life... */
			if (hosts.getHosts().containsKey(address)) {
				Host host = (Host)hosts.getHosts().get(address);
				host.getSessions().put(sid, session);
				session.put("host", address);
			}
			else {
				/* Do not fire an event if there is no host to associate session with */
				before.remove(sid);
				after.remove(sid);
			}

			/* track which sessions are synced and which are not */
			if ("".equals(session.get("info"))) {
				nonsync.add(sid);
			}
			else {
				syncz.add(sid);
			}
		}

		/* calculate the differences and fire some events based on them */
		Set newSessions = DataUtils.difference(after, before);
		fireSessionEvents("session_open", newSessions.iterator(), dataz);

		/* calculate sync events and fix the nonsync set */
		Set newsync = DataUtils.intersection(syncz, nonsync);
		fireSessionEvents("session_sync", newsync.iterator(), dataz);

		/* update our list of non-synced sessions */
		nonsync.removeAll(syncz);

		/* these are sessions that are new and sync'd -- fire events for them... */
		newSessions.removeAll(newsync); /* we already fired events for these */
		newSessions.retainAll(syncz);   /* keep anything that is synced */
		fireSessionEvents("session_sync", newSessions.iterator(), dataz);

		Set droppedSessions = DataUtils.difference(before, after);
		fireSessionEvents("session_close", droppedSessions.iterator(), dataz);

		Stack args = new Stack();
		args.push(FilterManager.convertAll(results));
		manager.fireEventAsync("sessions", args);

		initial = false;
	}
}

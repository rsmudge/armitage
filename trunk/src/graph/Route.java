package graph;

import java.util.*;

public class Route {
	/** convert a long to an ip address */
	public static long ipToLong(String address) {
		String[] quads = address.split("\\.");
		long result = 0;
		result += Integer.parseInt(quads[3]);
		result += Long.parseLong(quads[2]) << 8L;
		result += Long.parseLong(quads[1]) << 16L;
		result += Long.parseLong(quads[0]) << 24L;
		return result;
	}
		
	private static final long RANGE_MAX = ipToLong("255.255.255.255");

	protected long begin;
	protected long end;
	protected String gateway;

	/** create an object to represent a network and where it's routing through */
	public Route(String address, String networkMask, String gateway) {
		begin = ipToLong(address);
		end   = begin + (RANGE_MAX - ipToLong(networkMask));

		this.gateway = gateway;
	}

	/** return the gateway */
	public String getGateway() {
		return gateway;
	}

	/** check if this route applies to the specified network address */
	public boolean shouldRoute(String address) {
		long check = ipToLong(address);
		return check >= begin && check <= end;
	}
}

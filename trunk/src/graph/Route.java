package graph;

import java.util.*;

public class Route {
	/** convert a long to an ip address */
	public static long ipToLong(String address) {
		String[] quads = address.split("\\.");
		long result = 0;

		/* this is a fallback in case one of the IP addresses is malformed */
		if (quads.length != 4) 
			return 0L;

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

	public Route(String address) {
		String[] description = address.split("/");
		String host = "", network = "";

		if (description.length == 1) {
			host = address;

			String[] quads = address.split("\\.");
			if (quads[0].equals("0")) {
				network = "1";
			}
			else if (quads[1].equals("0")) {
				network = "8";
			}
			else if (quads[2].equals("0")) {
				network = "16";
			}
			else if (quads[3].equals("0")) {
				network = "24";
			}
			else {
				network = "32";
			}
		}
		else {
			host = description[0];
			network = description[1];
		}

		begin = ipToLong(host);
		try {
			end = begin + (RANGE_MAX >> Integer.parseInt(network));
		}
		catch (Exception ex) {
			System.err.println(network + " is malformed!");
		}
	}

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

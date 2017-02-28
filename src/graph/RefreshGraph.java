package graph;

import java.util.*;
import java.awt.Image;
import javax.swing.SwingUtilities;

public class RefreshGraph implements Runnable {
	protected List nodes = new LinkedList();
	protected List highlights = new LinkedList();
	protected List routes = new LinkedList();
	protected Refreshable graph = null;

	private static class Highlight  {
		public String gateway = "";
		public String host = "";
	}

	private static class Node {
		public String id = "";
		public String services = "";
		public String label = "";
		public String description = "";
		public Image  iconz = null;
		public String tooltip = "";
	}

	public RefreshGraph(Refreshable graph) {
		this.graph = graph;
	}

	/* call this when our data is built up and ready to be used to update our display */
	public void go() {
		SwingUtilities.invokeLater(this);
	}

	public void addRoute(Route route) {
		routes.add(route);
	}

	public void addNode(String id, String services, String label, String description, Image iconz, String tooltip) {
		Node n = new Node();
		n.id = id;
		n.services = services;
		n.label = label;
		n.description = description;
		n.iconz = iconz;
		n.tooltip = tooltip;
		nodes.add(n);
	}

	public void addHighlight(String gateway, String host) {
		Highlight h = new Highlight();
		h.gateway = gateway;
		h.host    = host;
		highlights.add(h);
	}

	public void run() {
		graph.start();

			/* add nodes to the graph */
			Iterator i = nodes.iterator();
			while (i.hasNext()) {
				Node n = (Node)i.next();
				graph.addNode(n.id, n.services, n.label, n.description, n.iconz, n.tooltip);
			}

			/* setup routes */
			graph.setRoutes((Route[])routes.toArray(new Route[0]));

			/* highlight routes */
			i = highlights.iterator();
			while (i.hasNext()) {
				Highlight h = (Highlight)i.next();
				graph.highlightRoute(h.gateway, h.host);
			}

			/* anything we didn't touch should go */
			graph.deleteNodes();


		graph.end();
	}
}

package graph;

import java.awt.Image;

public interface Refreshable {
	/* called to indicate that we're starting an update */
	public void start();

	/* add a node */
	public Object addNode(String id, String services, String label, String description, Image image, String tooltip);

	/* setup all of our routes in one fell swoop */
	public void setRoutes(Route[] routes);

	/* highlight a pivot line please */
	public void highlightRoute(String src, String dst);

	/* clear any untouched nodes */
	public void deleteNodes();

	/* called to indicate that we're ending an update */
	public void end();
}

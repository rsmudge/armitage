#
# Code to create/manage dynamic workspaces.
#

import msf.*;
import java.awt.*;
import java.io.*;
import java.net.*;
import javax.swing.*;
import javax.imageio.*;
import ui.*;

# create_workspace_menus($parent_menu, $active)
# dynamic workspaces... y0.
sub client_workspace_items {
	local('$index $workspace');

	item($1, 'Create', 'C', 
		lambda({
			local('$dialog $name $host $ports $os $button $session');
			$dialog = dialog("New Dynamic Workspace", 640, 480);
			[$dialog setLayout: [new GridLayout: 6, 1]];

			$name  = [new ATextField: 16];
			$host  = [new ATextField: 16];
			$ports = [new ATextField: 16];
			$os    = [new ATextField: 16];
			$session = [new JCheckBox: "Hosts with sessions only"];
			$button = [new JButton: "Add"];

			[$dialog add: label_for("Name:", 60, $name)]; 
			[$dialog add: label_for("Hosts:", 60, $host)]; 
			[$dialog add: label_for("Ports:", 60, $ports)]; 
			[$dialog add: label_for("OS:", 60, $os)]; 
			[$dialog add: $session];

			[$dialog add: center($button)];
			[$dialog pack];
			[$dialog show];

			[$button addActionListener: lambda({
				# yay, we have a dialog...
				local('$n $h $p $o $s');
				$n = [$name getText];
				$h = strrep([$host getText], '*', '%', '?', '_');
				$p = [$ports getText];
				$o = strrep([$os getText], '*', '%', '?', '_');
				$s = [$session isSelected];

				# save the new menu
				local('$menus');
				$menus = [$preferences getProperty: "armitage.workspaces.menus", ""];
				$menus = split('\|', $menus);
				push($menus, join("@@", @($n, $h, $p, $o, $s)));
				[$preferences setProperty: "armitage.workspaces.menus", join("!!", $menus)];
				savePreferences();

				# switch to it!
				thread(lambda({
					call($mclient, "db.filter", %(os => $o, ports => $p, hosts => $h, session => $s));
					refreshTargets();
				}, \$o, \$p, \$h, \$s));

				[$frame setTitle: "$TITLE - $n"];

				elog("switched to workspace: $n");

				# add the new menu back...
				[$parent removeAll];
				client_workspace_items($parent);

				[$dialog setVisible: 0];
			}, \$parent, \$dialog, \$host, \$ports, \$os, \$name, \$session)];
		}, $parent => $1));

	item($1, 'Reset', 'R', 
		lambda({
			[$preferences setProperty: "armitage.workspaces.menus", ""];
			savePreferences();
			[$frame setTitle: $TITLE];
			thread({ 
				call($mclient, "db.filter", %()); 
				refreshTargets();
			});
			[$parent removeAll];
			client_workspace_items($parent);
		}, $parent => $1));

	separator($1);

	item($1, "Show All", "S", {
		[$frame setTitle: $TITLE];
		thread({
			call($mclient, "db.filter", %());
			refreshTargets();
		});
		elog("removed workspace filter");
	});

	local('$menus $menu $name $host $ports $os $x $session');
	$menus = [$preferences getProperty: "armitage.workspaces.menus", ""];
	$menus = split('!!', $menus);
	foreach $x => $menu (filter({ return iff($1, $1); }, $menus)) {
		($name, $host, $ports, $os, $session) = split('@@', $menu);
		item($1, "$x $+ . $name", $x, lambda({
			thread(lambda({
				call($mclient, "db.filter", %(os => $os, ports => $ports, hosts => $host, session => $session));
				refreshTargets();
			}, \$os, \$ports, \$host, \$session));
			elog("switched to workspace: $name");
			[$frame setTitle: "$TITLE - $name"];
		}, \$host, \$ports, \$os, \$name, \$session));
	}
}


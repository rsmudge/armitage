#
# CRUD for Dynamic Workspaces
#

import msf.*;
import java.awt.*;
import java.io.*;
import java.net.*;
import javax.swing.*;
import javax.imageio.*;
import ui.*;

sub newWorkspace {
	workspaceDialog(%(), $1, $title => "New Dynamic Workspace", $button => "Add", $enable => 1);
}

sub editWorkspace {
	workspaceDialog($1, $2, $title => "Edit Dynamic Workspace", $button => "Save", $enable => $null);
}

sub updateWorkspaceList {
	[$1 setListData: cast(map({ return $1["name"]; }, workspaces()), ^Object)];
}

sub listWorkspaces {
	local('$dialog $list $add $edit $delete');
	$dialog = dialog("Workspaces", 640, 480);
	[$dialog setLayout: [new BorderLayout]];

	$list = [new JList];
	updateWorkspaceList($list);
	[$list setSelectionMode: [ListSelectionModel MULTIPLE_INTERVAL_SELECTION]];
	
	[$dialog add: [new JScrollPane: $list], [BorderLayout CENTER]];

	$add = [new JButton: "Add"];
	$edit = [new JButton: "Edit"];
	$delete = [new JButton: "Remove"];

	[$add addActionListener: lambda({
		newWorkspace($list);
	}, \$dialog, \$list)];

	[$delete addActionListener: lambda({
		local('%names $workspace @workspaces');
		putAll(%names, [$list getSelectedValues], { return 1; });
		@workspaces = workspaces();
		foreach $workspace (@workspaces) {
			if ($workspace['name'] in %names) {
				remove();
			}
		}
		saveWorkspaces(@workspaces);
		updateWorkspaceList($list);

		# add the new menu back...
		[$parent removeAll];
		client_workspace_items($parent);
	}, \$dialog, \$list, \$parent)];

	[$edit addActionListener: lambda({
		local('$sel $temp');
		$sel = [$list getSelectedValue];

		$temp = search(workspaces(), lambda({ 
			return iff($1["name"] eq $name, $1); 
		}, $name => $sel));

		if ($temp !is $null) {
			editWorkspace($temp, $list);
		}
	}, \$dialog, \$list)];

	[$dialog add: center($add, $edit, $delete), [BorderLayout SOUTH]];
	[$dialog pack];
	[$dialog show];
}

sub workspaceDialog {
	local('$dialog $name $host $ports $os $button $session');
	$dialog = dialog($title, 640, 480);
	[$dialog setLayout: [new GridLayout: 6, 1]];

	$name  = [new ATextField: $1['name'], 16];
	[$name setEnabled: $enable];
	$host  = [new ATextField: $1['hosts'], 16];
	$ports = [new ATextField: $1['ports'], 16];
	$os    = [new ATextField: $1['os'], 16];
	$session = [new JCheckBox: "Hosts with sessions only"];
	if ($1['sessions'] eq 1) {
		[$session setSelected: 1];
	}

	$button = [new JButton: $button];

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
		local('$n $h $p $o $s @workspaces $ws $temp');
		$n = [$name getText];
		$h = strrep([$host getText], '*', '%', '?', '_');
		$p = [$ports getText];
		$o = strrep([$os getText], '*', '%', '?', '_');
		$s = [$session isSelected];

		# save the new menu
		$ws = workspace($n, $h, $p, $o, $s);
		@workspaces = workspaces();
		foreach $temp (@workspaces) {
			if ($temp["name"] eq $n) {
				$temp = $ws;
				$ws = $null;
			}
		}

		if ($ws !is $null) {
			push(@workspaces, $ws);
		}
		saveWorkspaces(@workspaces);
		updateWorkspaceList($list);
		[$dialog setVisible: 0];

		# add the new menu back...
		[$parent removeAll];
		client_workspace_items($parent);
	}, \$parent, \$dialog, \$host, \$ports, \$os, \$name, \$session, $list => $2)];
}

# create_workspace_menus($parent_menu, $active)
# dynamic workspaces... y0.
sub client_workspace_items {
	local('$index $workspace');
	let(&workspaceDialog, $parent => $1);
	let(&listWorkspaces, $parent => $1);

	item($1, 'Manage', 'M', {
		listWorkspaces();
	});

	separator($1);

	item($1, "Show All", "S", {
		[$frame setTitle: $TITLE];
		thread({
			call($mclient, "db.filter", %());
			refreshTargets();
		});
		elog("removed workspace filter");
	});

	local('$x $workspace $name');
	foreach $x => $workspace (workspaces()) {
		$name = $workspace['name'];
		item($1, "$x $+ . $+ $name", $x, lambda({
			thread(lambda({
				call($mclient, "db.filter", $workspace);
				refreshTargets();
			}, \$workspace));
			elog("switched to workspace: $name");
			[$frame setTitle: "$TITLE - $name"];
		}, $workspace => copy($workspace), \$name));
	}
}

sub workspace {
	return ohash(name => $1, hosts => $2, ports => $3, os => $4, session => $5);
}

sub workspaces {
	local('$ws @r $name $host $port $os $session $workspace');
	$ws = split("!!", [$preferences getProperty: "armitage.workspaces.menus", ""]);
	foreach $workspace ($ws) {
		if ($workspace ne "") {
			($name, $host, $port, $os, $session) = split('@@', $workspace);
			push(@r, workspace($name, $host, $port, $os, $session));
		}
	}
	return @r;
}

sub saveWorkspaces {
	[$preferences setProperty: "armitage.workspaces.menus", join("!!", map({ return join("@@", values($1)); }, $1))];
	savePreferences();	
}

#
# Process Browser (for Meterpreter)
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;
import ui.*;

sub createModuleBrowser {
	local('$tree $split $scroll1 $t $2');
	$split = [new JSplitPane: [JSplitPane HORIZONTAL_SPLIT], createModuleList(ohash(auxiliary => buildTree(@auxiliary), exploit => buildTree(@exploits), post => buildTree(@post), payload => buildTree(@payloads))), iff($1, $1, [new JPanel])];
	[$split setOneTouchExpandable: 1];
	return $split;
}

sub showModulePopup {
	local('$menu');
	if (($2 eq "exploit" && "*/browser/*" !iswm $3 && "*/fileformat/*" !iswm $3) || ($2 eq "auxiliary" && "*_login" iswm $3)) {
		$menu = [new JPopupMenu];
		item($menu, "Relevant Targets", 'R', lambda({
			thread(lambda({
				local('$options %filter $os');
				$options = call($client, "module.options", $type, $module);
				
				if ("RPORT" in $options) {
					%filter["ports"] = $options['RPORT']['default'];

					if (%filter["ports"] eq '445') {
						%filter["ports"] .= ", 139";
					}
					else if (%filter["ports"] eq '80') {
						%filter["ports"] .= ", 443";
					}
				}

				$os = split('/', $module)[0];
				if ($os eq "windows") {
					%filter["os"] = "windows";
				}	
				else if ($os eq "linux") {
					%filter["os"] = "linux";
				}
				else if ($os eq "osx") {
					%filter["os"] = "ios, mac";
				}

				if (size(%filter) > 0) {
					call($client, "db.filter", %filter);
					[$frame setTitle: "$TITLE - $module"]
					showError("Created a dynamic workspace for this module.\nUse Workspaces -> Show All to see all hosts.");
				}
				else {
					showError("I'm sorry, this option doesn't work for\nthis module.");
				}
			}, \$module, \$type));
		}, $module => $3, $type => $2));

		[$menu show: [$1 getSource], [$1 getX], [$1 getY]];
	}
}

sub createModuleList {
	local('$tree $split $scroll1 $t');
	$tree = [new JTree: treeNodes($null, $1)];
	[$tree setRootVisible: 0];

	[$tree addMouseListener: lambda({
		local('$t');
		$t = [$1 isPopupTrigger];
		if ($t == 0 && ($0 ne "mousePressed" || [$1 getClickCount] < 2)) { 
			return;
		}

		local('$p');
		$p = [[$1 getSource] getPathForLocation: [$1 getX], [$1 getY]];
		if ($p is $null) {
			return;
		}
		else if ([$1 isPopupTrigger]) {
			local('$selected $type $path');
			$selected = map({ return "$1"; }, [$p getPath]);
			$type = $selected[1];
			$path = join('/', sublist($selected, 2));
			showModulePopup($1, $type, $path);
			return;
		}

		thread(lambda({
			local('$selected $type $path');
			$selected = map({ return "$1"; }, [$p getPath]);
			if (size($selected) > 2) {
				$type = $selected[1];
				$path = join('/', sublist($selected, 2));
				if ($path in @exploits || $path in @auxiliary || $path in @payloads || $path in @post) {
					if ($type eq "exploit") {
						if ('browser' in $selected || 'fileformat' in $selected) {
							launch_dialog($path, $type, $path, 1, [$targets getSelectedHosts]);
						}
						else {
							local('$a $b');
							$a = call($client, "module.info", "exploit", $path);
							$b = call($client, "module.options", "exploit", $path);
							dispatchEvent(lambda({
								attack_dialog($a, $b, [$targets getSelectedHosts], $path);
							}, \$a, \$b, \$targets, \$path));
						}
					}
					else {
						launch_dialog($path, $type, $path, 1, [$targets getSelectedHosts]);
					}
				}
			}
		}, \$p));
	})];

	$scroll1 = [new JScrollPane: $tree, [JScrollPane VERTICAL_SCROLLBAR_AS_NEEDED], [JScrollPane HORIZONTAL_SCROLLBAR_NEVER]];

	local('$search $button');
	$search = [new ATextField: 10];
	[$search setToolTipText: "Enter a query to filter the MSF modules"];
	[$search addActionListener: lambda({
		local('$model');
		if ([$1 getActionCommand] ne "") {
			local('$filter %list $a $e $p $o $x');
			$filter = lambda({ return iff(lc("* $+ $s $+ *") iswm lc($1), $1); }, $s => [$1 getActionCommand]);
			%list = ohash();
			$a = filter($filter, @auxiliary);
			$e = filter($filter, @exploits);
			$p = filter($filter, @payloads);
			$o = filter($filter, @post);
			if (size($a) > 0) { %list["auxiliary"] = buildTree($a); }
			if (size($e) > 0) { %list["exploit"] = buildTree($e); }
			if (size($p) > 0) { %list["payload"] = buildTree($p); }
			if (size($o) > 0) { %list["post"] = buildTree($o); }
			$model = treeNodes($null, %list);
			[[$tree getModel] setRoot: $model];

			for ($x = 0; $x < [$tree getRowCount]; $x++) {
				[$tree expandRow: $x];
			}
			[$search setText: ""];
		}
		else {
			$model = treeNodes($null, $original);
			[[$tree getModel] setRoot: $model];
		}
	}, $original => $1, \$tree, \$search)];
	
	local('$panel');
	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	[$panel add: $scroll1, [BorderLayout CENTER]];
	[$panel add: wrapComponent($search, 5), [BorderLayout SOUTH]];

	[$panel setPreferredSize: [new Dimension: 180, 600] ];
	[$panel setMinimumSize: [new Dimension: 180, 0]];

	let(&showPostModules, \$tree, \$search)
	return $panel;
}

# shows the post modules compatible with a session... for this to work, the
# code that creates the module browser must call: let(&showPostModules, $tree => ..., $search => ...)
sub showPostModules {
	local('@allowed $2');
	@allowed = getOS(sessionToOS($1));
	fork({
		local('$modules %list $model');
		$modules = call($client, "session.compatible_modules", $sid)["modules"];
		$modules = map({ return substr($1, 5); }, $modules);

		# filter out operating systems.
		$modules = filter(lambda({ 
			local('$o');
			($o) = split('/', $1);
			return iff($o in @allowed, $1);		
		}, \@allowed), $modules);

		# filter out other stuff if a filter exists...
		if ($filter !is $null) {
			$modules = filter(lambda({ return iff($filter iswm $1, $1); }, \$filter), $modules);
		}

		%list = ohash(post => buildTree($modules));
		$model = treeNodes($null, %list);

		dispatchEvent(lambda({
			local('$x');
			[[$tree getModel] setRoot: $model];

			for ($x = 0; $x < [$tree getRowCount]; $x++) {
				[$tree expandRow: $x];
			}
			[$search setText: ""];
		}, \$search, \$tree, \$model));
	}, \$tree, \$search, $sid => $1, \$client, \@allowed, $filter => $2);
}

sub createModuleBrowserTab {
	[$frame addTab: "Modules", createModuleBrowser(), $null];
}

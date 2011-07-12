#
# Process Browser (for Meterpreter)
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

sub createModuleBrowser {
	local('$tree $split $scroll1 $t $2');
	$split = [new JSplitPane: [JSplitPane HORIZONTAL_SPLIT], createModuleList(ohash(auxiliary => buildTree(@auxiliary), exploit => buildTree(@exploits), post => buildTree(@post), payload => buildTree(@payloads))), iff($1, $1, [new JPanel])];
	[$split setOneTouchExpandable: 1];
	return $split;
}

sub createModuleList {
	local('$tree $split $scroll1 $t');
	$tree = [new JTree: treeNodes($null, $1)];
	[$tree setRootVisible: 0];

	[$tree addMouseListener: lambda({
		if ($0 ne "mousePressed" || [$1 getClickCount] < 2) {
			return;
		}

		local('$p');
		$p = [[$1 getSource] getPathForLocation: [$1 getX], [$1 getY]];
		if ($p is $null) {
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
	$search = [new JTextField: 10];
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

	let(&showPostModules, \$tree, \$search)
	return $panel;
}

# shows the post modules compatible with a session... for this to work, the
# code that creates the module browser must call: let(&showPostModules, $tree => ..., $search => ...)
sub showPostModules {
	local('@allowed');
	@allowed = getOS(sessionToOS($1));
	fork({
		local('$modules %list $model');
		$modules = call($client, "session.compatible_modules", $sid)["response"];
		$modules = map({ return substr($1, 5); }, $modules);

		# filter out operating systems.
		$modules = filter(lambda({ 
			local('$o');
			($o) = split('/', $1);
			return iff($o in @allowed, $1);		
		}, \@allowed), $modules);

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
	}, \$tree, \$search, $sid => $1, \$client, \@allowed);
}

sub createModuleBrowserTab {
	[$frame addTab: "Modules", createModuleBrowser(), $null];
}

#
# Loot browser (not yet complete... on hold until more post/ modules have loot)
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

sub updateDownloadModel {
	thread(lambda({
		local('$root $files $entry $findf $hosts $host');

		[$model clear: 256];

		$files = @();
		$root = getFileProper(systemProperties()["user.home"], ".armitage", "downloads");
		$findf = {
			if (-isDir $1) {
				return map($this, ls($1));
			}
			else {
				return %(
					host => $host,
					file => getFileName($1), 
					size => lof($1), 
					updated_at => lastModified($1),
					location => $1,
					path => substr(strrep(getFileParent($1), $root, ''), 1)
				);
			}
		};

		$hosts = map({ return getFileName($1); }, ls($root));
		foreach $host ($hosts) {
			addAll($files, flatten(
				map(
					lambda($findf, $root => getFileProper($root, $host), \$host), 
					ls(getFileProper($root, $host))
			)));
		}
		
		foreach $entry ($files) {
			$entry["date"] = rtime($entry["updated_at"] / 1000.0);
			[$model addEntry: $entry];
		}
		[$model fireListeners];
	}, \$model));
}

sub showDownload {
	local('$v');
	$v = [$model getSelectedValue: $table];

	if ($v !is $null) {
		if ($client is $mclient) {
			[gotoFile([new java.io.File: getFileParent($v)])];
		}
		else {
			local('$name $save');
			$name = [$model getSelectedValueFromColumn: $table, "name"];
			$save = getFileName($name);
			thread(lambda({
				local('$handle $data');
				$data = getFileContent($v);
				$handle = openf("> $+ $save");
				writeb($handle, $data);
				closef($handle);
				[gotoFile([new java.io.File: cwd()])];
			}, \$v, \$save));
		}
		return;
	}
}

sub createDownloadBrowser {
	local('$table $model $panel $refresh $sorter $host');

	$model = [new GenericTableModel: @("host", "file", "path", "size", "date"), "location", 16];

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$table = [new JTable: $model];
	setupSizeRenderer($table, "size");
	$sorter = [new TableRowSorter: $model];
        [$sorter toggleSortOrder: 0];
	[$sorter setComparator: 0, &compareHosts];
	[$sorter setComparator: 4, {
		return convertDate($1) <=> convertDate($2);
	}];
	[$table setRowSorter: $sorter];

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	[$table addMouseListener: lambda({
		if ($0 eq "mousePressed" && [$1 getClickCount] >= 2) {
			showDownload(\$model, \$table);
		}
	}, \$model, \$table)];

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		updateDownloadModel(\$model);	
	}, \$model)];

	updateDownloadModel(\$model); 		

	[$panel add: center($refresh), [BorderLayout SOUTH]];

	[$frame addTab: "Downloads", $panel, $null];
}

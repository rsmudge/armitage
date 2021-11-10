#
# Loot browser (not yet complete... on hold until more post/ modules have loot)
#

import table.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

import ui.*;

sub updateLootModel {
	fork({
		local('$loots $entry');
		[$model clear: 16];
		$loots = call($mclient, "db.loots")["loots"];
		foreach $entry ($loots) {
			$entry["date"] = rtime($entry["updated_at"] / 1000L);
			$entry["type"] = $entry["ltype"];
			[$model addEntry: $entry];
		}
		[$model fireListeners];
	}, \$model, \$mclient);
}

sub downloadLoot {
	[lambda({
		local('$dest');
		$dest = getFileProper(dataDirectory(), $type);
		mkdir($dest);
		[lambda(&_downloadLoot): \$model, \$table, \$getme, \$dest, $dtype => $type];
	}, \$model, \$table, \$getme, \$type)];
}

sub _downloadLoot {
	local('$total $index $loot $entries $host $location $name $type $when $path @downloads @errors $progress $size $did $download $handle $data $file $x $read $pct');

	$entries = [$model getSelectedValuesFromColumns: $table, @('host', $getme, 'name', 'content_type', 'updated_at', 'path')];
	$total = 0;
	$read  = 0;

	# get our download ids and figure out how much data we have to download
	foreach $index => $loot ($entries) {
		($host, $location, $name, $type, $when, $path) = $loot;

		call_async_callback($mclient, "armitage.download_start", $this, $location);
		yield;
		$1 = convertAll($1);
		if ('error' in $1) {
			push(@errors, "$name $+ : $1");
		}
		else {
			push(@downloads, @($host, $path, $name, $type, $1['size'], $1['id']));
			$total += $1['size'];
		}
	}

	# create our progress monitor...
	$progress = [new ProgressMonitor: $frame, "Download Data", "", 0, $total];

	# go through each file, one at a time, and grab it...
	foreach $download (@downloads) {
		($host, $path, $name, $type, $size, $did) = $download;
		$host = strrep($host, ':', '_');

		[$progress setNote: "$name"];

		# make the folder to store our downloads into
		if ($dtype eq "downloads") {
			$file = getFileProper($dest, $host, strrep($path, ':', ''), $name);
		}
		else {
			$file = getFileProper($dest, $host, $name);
		}
		mkdir(getFileParent($file));

		# start to download the file contents...
		$handle = openf("> $+ $file");

		for ($x = 0; $x < $size && ![$progress isCanceled];) {
			call_async_callback($mclient, "armitage.download_next", $this, $did);
			yield;
			$1 = convertAll($1);

			writeb($handle, $1['data']);
			$read += strlen($1['data']);
			$x    += strlen($1['data']);
			[$progress setProgress: $read];
			$pct   = round((double($x) / $size) * 100, 1);

			[$progress setNote: "$[-4]pct $+ % of $name"];
		}

		# are we there yet?
		closef($handle);

		if ([$progress isCanceled]) {
			break;
		}
	}

	# let's clean up after ourselves...
	foreach $download (@downloads) {
		($host, $path, $name, $type, $size, $did) = $download;
		call_async($mclient, "armitage.download_stop", $this, $did);
	}

	dispatchEvent(lambda({
		[$progress close];
		showError("File(s) saved to:\n $+ $dest");
		[gotoFile([new java.io.File: $dest])];
	}, \$dest, \$progress));
}

sub showLoot {
	thread(lambda(&_showLoot, \$model, \$table, \$getme));
}

sub _postLoot {
	local('$host $location $name $type $when');
	($host, $location, $name, $type, $when) = $1;

	[$2 append: "
\c9#
\c9# $host $+ : $name 
\c9#\n"];

	if ("*binary*" iswm $type) {
		[$2 append: "\c4This is a binary file\n"];
	}
	else {
		[$2 append: getFileContent($location)];
	}
}

sub _showLoot {
	local('$loot $entries $dialog $display $refresh');

	$dialog = [new JPanel];
	[$dialog setLayout: [new BorderLayout]];
	$display = [new console.Display: $preferences];

	$entries = [$model getSelectedValuesFromColumns: $table, @('host', $getme, 'name', 'content_type', 'updated_at')];

	foreach $loot ($entries) {
		_postLoot($loot, $display);
		yield 10;
	}

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		local('$r');
		$r = [[$display console] getVisibleRect];
		[$display setText: ""];
		thread(lambda({
			local('$loot');

			foreach $loot ($entries) {
				_postLoot($loot, $display);
				yield 10;
			}

			dispatchEvent(lambda({
				[[$display console] scrollRectToVisible: $r];
			}, \$display, \$r));
		}, \$entries, \$display, \$r));
	}, \$entries, \$display)];

	[$dialog add: $display, [BorderLayout CENTER]];
	[[$display console] scrollRectToVisible: [new Rectangle: 0, 0, 0, 0]];
	[$dialog add: center($refresh), [BorderLayout SOUTH]];
	[$frame addTab: "View", $dialog, $null, $null];
}

sub createLootBrowser {
	local('$table $model $panel $refresh $view $sorter $host $sync');

	$model = [new GenericTableModel: @("host", "type", "info", "date"), "path", 16];

	$panel = [new JPanel];
	[$panel setLayout: [new BorderLayout]];

	$table = [new ATable: $model];
	$sorter = [new TableRowSorter: $model];
        [$sorter toggleSortOrder: 0];
	[$sorter setComparator: 0, &compareHosts];
	[$sorter setComparator: 3, {
		return convertDate($1) <=> convertDate($2);
	}];
	[$table setRowSorter: $sorter];

	[$panel add: [new JScrollPane: $table], [BorderLayout CENTER]];

	$view = [new JButton: "View"];

	addMouseListener($table, lambda({
		if ($0 eq "mousePressed" && [$1 getClickCount] >= 2) {
			showLoot(\$model, \$table, $getme => "path");
		}
	}, \$model, \$table));

	$sync = [new JButton: "Sync Files"];
	[$sync addActionListener: lambda({
		downloadLoot(\$model, \$table, $getme => "path", $type => "loots");
	}, \$model, \$table)];

	[$view addActionListener: lambda({
		showLoot(\$model, \$table, $getme => "path");
	}, \$model, \$table)];

	$refresh = [new JButton: "Refresh"];
	[$refresh addActionListener: lambda({
		updateLootModel(\$model);	
	}, \$model)];

	updateLootModel(\$model); 		

	if ($client is $mclient) {
		[$panel add: center($view, $refresh), [BorderLayout SOUTH]];
	}
	else {
		[$panel add: center($view, $sync, $refresh), [BorderLayout SOUTH]];
	}

	[$frame addTab: "Loot", $panel, $null];
}

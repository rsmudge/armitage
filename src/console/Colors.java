package console;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.text.*;

/* a class for managing and parsing colors */
public class Colors {
	public static final char bold      = (char)2;
	public static final char underline = (char)31;
	public static final char color     = (char)3;
	public static final char cancel    = (char)15;
	public static final char reverse   = (char)22;

	private static final class Fragment {
		protected SimpleAttributeSet attr = new SimpleAttributeSet();
		protected StringBuffer text = new StringBuffer(32);
		protected Fragment next     = null;

		public void advance() {
			next = new Fragment();
			next.attr = (SimpleAttributeSet)attr.clone();
		}
	}

	public static Color colorTable[] = new Color[17];
	static {
		colorTable[0] = Color.lightGray;
		colorTable[1] = new Color(0, 0, 0);
		colorTable[2] = new Color(0, 0, 128);
		colorTable[3] = new Color(0, 144, 0);
		colorTable[4] = new Color(255, 0, 0);
		colorTable[5] = new Color(128, 0, 0);
		colorTable[6] = new Color(160, 0, 160);
		colorTable[7] = new Color(255, 128, 0);
		colorTable[8] = new Color(255, 255, 0);
		colorTable[9] = new Color(0, 255, 0);
		colorTable[10] = new Color(0, 144, 144);
		colorTable[11] = new Color(0, 255, 255);
		colorTable[12] = new Color(0, 0, 255);
		colorTable[13] = new Color(255, 0, 255);
		colorTable[14] = new Color(128, 128, 128);
		colorTable[15] = Color.lightGray;
		colorTable[16] = new Color(255, 255, 255);
	}

	public static void append(JTextPane console, String text) {
		StyledDocument doc = console.getStyledDocument();
		Fragment f = parse(text);
		while (f != null) {
			try {
				if (f.text.length() > 0)
					doc.insertString(doc.getLength(), f.text.toString(), f.attr);
			}
			catch (Exception ex) {
				ex.printStackTrace();
			}
			f = f.next;
		}
	}

	public static void set(JTextPane console, String text) {
		console.setText("");
		append(console, text);
	}

	private static Fragment parse(String text) {
		Fragment current = new Fragment();
		Fragment first = current;
		char[] data = text.toCharArray();
		int fore, back;

		for (int x = 0; x < data.length; x++) {
			switch (data[x]) {
				case bold:
					current.advance();
					StyleConstants.setBold(current.next.attr, !StyleConstants.isBold(current.attr));
					current = current.next;
					break;
				case underline:
					current.advance();
					StyleConstants.setUnderline(current.next.attr, !StyleConstants.isUnderline(current.attr));
					current = current.next;
					break;
				case color:     /* look for 0-9a-f = 16 colors */
					current.advance();
					if ((x + 1) < data.length && ((data[x + 1] >= '0' && data[x + 1] <= '9') || (data[x + 1] >= 'A' && data[x + 1] <= 'F'))) {
						int index = Integer.parseInt(data[x + 1] + "", 16);
						StyleConstants.setForeground(current.next.attr, colorTable[index]);
						x += 1;
					}
					current = current.next;
					break;
				case '\n':
					current.advance();
					current = current.next;
					current.attr = new SimpleAttributeSet();
					current.text.append(data[x]);
					break;
				case cancel:
					current.advance();
					current = current.next;
					current.attr = new SimpleAttributeSet();
					break;
				default:
					current.text.append(data[x]);
			}
		}
		return first;
	}
}

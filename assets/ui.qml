import bb.cascades 1.0
import bb.system 1.0

NavigationPane {
	onCreationCompleted: {
		app.ResetHeadlines.connect(function() {
			feedItems.clear();
			indicator.start();
		});

		app.NewHeadline.connect(function(title, link, summary, pubDate) {
			indicator.stop();
			feedItems.insert({title: title, link: link, summary: summary, pubDate: pubDate});
		});

		app.Error.connect(function(msg) {
			errorDialog.cancelButton.label = "";
			errorDialog.body = msg;
			errorDialog.show();
		});

		app.refresh();
	}

	Page {
		Container {
			Container {
				layout: StackLayout {
					orientation: LayoutOrientation.LeftToRight
				}

				ActivityIndicator {
					id: indicator

					preferredHeight: 128
					preferredWidth: 128
					layoutProperties: StackLayoutProperties {
						spaceQuota: -1
					}
				}

				Label {
					text: "CBC"
					textStyle {
						base: SystemDefaults.TextStyles.BigText
					}

					preferredHeight: 128
					verticalAlignment: VerticalAlignment.Center
					layoutProperties: StackLayoutProperties {
						spaceQuota: 2
					}
				}
			}

			ListView {
				dataModel: GroupDataModel {
					id: feedItems

					sortedAscending: false
					grouping: ItemGrouping.None // TODO: I'd like to group by day only
					sortingKeys: ["pubDate"]
				}

				// Use a ListItemComponent to determine which property in the
				// data model is displayed for each list item
				listItemComponents: [
					ListItemComponent {
						type: "item"

						StandardListItem {
							title: ListItemData.title
							description: Qt.formatDateTime(ListItemData.pubDate)
						}
					}
				]

				onTriggered: {
					var selectedItem = dataModel.data(indexPath);
					invokeBrowser.query.uri = selectedItem.link;
					invokeBrowser.trigger("bb.action.OPEN");
				}

				attachedObjects: [
					Invocation {
						id: invokeBrowser

						query: InvokeQuery {
							uri: ""
						}
					}
				]
			}
		}
	}

	attachedObjects: [
		SystemDialog {
			id: errorDialog
			title: "Error"
			body: ""
		}
	]
}

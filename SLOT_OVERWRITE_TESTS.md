# Manual tests for slot overwrite fix

Hit ctrl+cmd+B before and after each test to isolate logs per scenario.

## Test 1: Original bug

1. cmd+1+J → tile kitty fullscreen
2. cmd+8+J → tile Slack fullscreen
3. cmd+5+L → tile WhatsApp to right
4. **Expected:** Slack displaced to left. WhatsApp on right. kitty invisible behind both (cleared from list).

## Test 2: Reverse direction

1. cmd+1+J → tile kitty fullscreen
2. cmd+8+J → tile Slack fullscreen
3. cmd+5+H → tile WhatsApp to left
4. **Expected:** Slack displaced to right. WhatsApp on left. kitty invisible (cleared from list).

## Test 3: Passive focus triggers displacement

1. cmd+1+J → tile kitty fullscreen
2. cmd+8+J → tile Slack fullscreen
3. Cmd-Tab to WhatsApp (WhatsApp must have been previously tiled to right half)
4. **Expected:** displaceIfHalf detects WhatsApp as right half, displaces Slack to left.

## Test 4: Pruning — resized app not displaced

1. cmd+1+J → tile kitty fullscreen
2. cmd+8+J → tile Slack fullscreen
3. Manually drag-resize Slack's window so it's no longer fullscreen-sized
4. cmd+5+L → tile WhatsApp to right
5. **Expected:** Slack pruned (resized). kitty displaced to left instead.

## Test 5: Multi-screen

1. cmd+1+J → tile kitty fullscreen (note which display)
2. Move focus to different display
3. cmd+5+L → tile WhatsApp to right on the other display
4. **Expected:** No displacement. WhatsApp just tiles to right. kitty untouched on its display.

## Test 6: Stale entries cleared after displacement

1. cmd+1+J → tile kitty fullscreen
2. cmd+8+J → tile Slack fullscreen
3. cmd+3+J → tile a third app fullscreen (list is now [kitty, slack, third])
4. cmd+5+L → tile WhatsApp to right
5. **Expected:** Third app displaced to left. kitty and Slack cleared from list.
6. cmd+5+J → tile WhatsApp fullscreen
7. cmd+6+H → tile another app to left
8. **Expected:** WhatsApp displaced to right. No ghost kitty/Slack displacement.
